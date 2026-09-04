"""Inventory listing, editing, and stock movements (TRD 4)."""
from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...core.db import get_db, utcnow
from ...core.security import current_vendor
from ...models import InventoryItem, Transaction, Vendor
from ...schemas import (
    ItemCreate,
    ItemDetailOut,
    ItemOut,
    ItemUpdate,
    MovementIn,
    StockAdviceOut,
    TransactionOut,
)
from ...services.catalog import shelf_life_for
from ...services.forecasting import forecast_item
from ...services.safety_stock import compute_reorder_point
from ...services.reactions import on_stock_changed
from ...services.sync import MOVEMENT_SIGN

router = APIRouter(prefix="/inventory", tags=["inventory"])


def _sales_history(db: Session, item_id: uuid.UUID, days: int = 120):
    since = utcnow() - timedelta(days=days)
    rows = db.execute(
        select(Transaction.occurred_at, Transaction.qty).where(
            Transaction.item_id == item_id,
            Transaction.type == "sale",
            Transaction.occurred_at >= since,
        )
    ).all()
    return [(ts.date(), float(qty)) for ts, qty in rows]


def _recent_daily(history: list[tuple[date, float]], days: int = 21) -> list[float]:
    """Collapse recent sales into a dense daily list for the safety-stock model."""
    if not history:
        return []
    end = max(d for d, _ in history)
    start = end - timedelta(days=days - 1)
    totals: dict[date, float] = defaultdict(float)
    for d, q in history:
        if d >= start:
            totals[d] += q
    return [totals.get(start + timedelta(days=i), 0.0) for i in range(days)]


def refresh_reorder_point(db: Session, item: InventoryItem, vendor: Vendor) -> StockAdviceOut:
    """Recompute and persist the dynamic reorder point for one item.

    Called whenever an item is read in detail or a movement is recorded, which
    is what makes the threshold live rather than a number set once and forgotten
    (TC-F03).
    """
    history = _sales_history(db, item.id)
    daily = _recent_daily(history)

    forecast_daily: list[float] = []
    if history:
        fc = forecast_item(
            item_id=str(item.id),
            sku_name=item.sku_name,
            category_key=item.category,
            history=history,
            horizon_days=max(3, vendor.supplier_lead_days),
            lat=vendor.lat or 18.52,
            lon=vendor.lon or 73.86,
        )
        forecast_daily = [d.predicted for d in fc.days]

    advice = compute_reorder_point(
        recent_daily_demand=daily,
        category_key=item.category,
        lead_days=vendor.supplier_lead_days,
        current_qty=item.current_qty,
        forecast_daily=forecast_daily,
    )

    item.reorder_point = advice.reorder_point
    db.commit()

    return StockAdviceOut(
        reorder_point=advice.reorder_point,
        safety_stock=advice.safety_stock,
        mean_daily_demand=advice.mean_daily_demand,
        days_of_cover=advice.days_of_cover,
        capped_by_shelf_life=advice.capped_by_shelf_life,
        reason=advice.reason,
        suggested_order_qty=advice.suggested_order_qty,
    )


@router.get("", response_model=list[ItemOut])
def list_inventory(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    low_only: bool = Query(False, description="Only items at or below reorder point"),
    category: str | None = None,
):
    stmt = select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
    if category:
        stmt = stmt.where(InventoryItem.category == category)

    items = db.scalars(stmt.order_by(InventoryItem.sku_name)).all()
    if low_only:
        items = [i for i in items if i.current_qty <= i.reorder_point]

    return [ItemOut.model_validate(i) for i in items]


@router.post("", response_model=ItemOut, status_code=201)
def create_item(
    body: ItemCreate,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    item = InventoryItem(
        id=body.id or uuid.uuid4(),
        vendor_id=vendor.id,
        sku_name=body.sku_name,
        category=body.category,
        current_qty=body.current_qty,
        unit=body.unit,
        unit_cost=body.unit_cost,
        unit_price=body.unit_price,
        shelf_life_days=shelf_life_for(body.category),
    )
    db.add(item)
    db.commit()
    refresh_reorder_point(db, item, vendor)
    return ItemOut.model_validate(item)


def _owned_item(db: Session, vendor: Vendor, item_id: uuid.UUID) -> InventoryItem:
    """Fetch an item, scoped to the authenticated vendor.

    Every item lookup goes through here. A 404 (not 403) is returned for
    another vendor's row, so the API does not confirm that an id exists.
    """
    item = db.scalar(
        select(InventoryItem).where(
            InventoryItem.id == item_id, InventoryItem.vendor_id == vendor.id
        )
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    return item


@router.get("/{item_id}", response_model=ItemDetailOut)
def get_item(
    item_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    item = _owned_item(db, vendor, item_id)
    advice = refresh_reorder_point(db, item, vendor)
    detail = ItemDetailOut.model_validate(item)
    detail.advice = advice
    detail.is_low = item.current_qty <= item.reorder_point
    return detail


@router.patch("/{item_id}", response_model=ItemOut)
def update_item(
    item_id: uuid.UUID,
    body: ItemUpdate,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    item = _owned_item(db, vendor, item_id)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    if body.category:
        item.shelf_life_days = shelf_life_for(body.category)
    item.last_updated = utcnow()
    db.commit()
    return ItemOut.model_validate(item)


@router.delete("/{item_id}", status_code=204)
def delete_item(
    item_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    db.delete(_owned_item(db, vendor, item_id))
    db.commit()


@router.post("/movement", response_model=TransactionOut, status_code=201)
def record_movement(
    body: MovementIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Record a sale, restock, or wastage against an item.

    The online path. Offline the same movement is queued on the device and
    arrives through `/sync/batch`, which applies identical rules.
    """
    item = _owned_item(db, vendor, body.item_id)

    # Captured before the mutation: the stockout detector is edge-triggered,
    # so it needs the value on the other side of the crossing.
    previous_qty = item.current_qty

    sign = MOVEMENT_SIGN[body.movement]
    item.current_qty = max(0.0, item.current_qty + sign * body.qty)
    item.last_updated = utcnow()

    if body.movement == "restock":
        shelf = shelf_life_for(item.category)
        if shelf:
            # A restock resets the countdown: the newest batch is what the
            # vendor will sell, so the old expiry no longer describes the shelf.
            item.expires_on = utcnow() + timedelta(days=shelf)
            item.shelf_life_days = shelf

    txn = Transaction(
        vendor_id=vendor.id,
        item_id=item.id,
        type=body.movement,
        qty=body.qty,
        unit_value=item.unit_price if body.movement == "sale" else item.unit_cost,
        source=body.source,
        confidence=body.confidence,
        raw_text=body.raw_text,
        occurred_at=body.occurred_at or utcnow(),
    )
    db.add(txn)
    db.commit()

    refresh_reorder_point(db, item, vendor)

    # After the reorder point is refreshed, so a crossing is judged against
    # the threshold this sale actually produced rather than a stale one.
    on_stock_changed(
        db,
        vendor=vendor,
        item=item,
        previous_qty=previous_qty,
        was_sale=body.movement == "sale",
    )
    db.commit()

    return TransactionOut.model_validate(txn)


@router.get("/{item_id}/transactions", response_model=list[TransactionOut])
def item_transactions(
    item_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    limit: int = Query(50, le=200),
):
    _owned_item(db, vendor, item_id)
    rows = db.scalars(
        select(Transaction)
        .where(Transaction.item_id == item_id)
        .order_by(Transaction.occurred_at.desc())
        .limit(limit)
    ).all()
    return [TransactionOut.model_validate(t) for t in rows]
