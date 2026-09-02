"""The vendor's side of the marketplace: distributors, sourcing, orders, ledger.

Everything here is scoped by `current_vendor`. A shop can only ever read its
own orders, its own connections and its own balances, and the supplier id on
every request is checked against a connection rather than trusted.
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ...core.db import get_db, utcnow
from ...core.security import current_vendor
from ...models import (
    CatalogEntry,
    InventoryItem,
    LedgerEntry,
    PurchaseOrder,
    Supplier,
    Vendor,
    VendorDistributor,
)
from ...schemas import (
    ConnectIn,
    ConnectionOut,
    LedgerLineOut,
    LedgerOut,
    OrderCancelIn,
    OrderCreateIn,
    OrderEventOut,
    OrderFulfilIn,
    OrderLineOut,
    OrderOut,
    SourcingOptionOut,
    SourcingOut,
    SupplierCardOut,
)
from ...services.connections import ConnectionError_, connect, disconnect
from ...services.ordering import (
    OrderError,
    amend_lines,
    apply_delivery,
    build_order,
    fill_rate,
    summarise_ledger,
    transition,
)
from ...services.sourcing import daily_rate, days_of_cover, haversine_km, rank_options

router = APIRouter(tags=["marketplace"])


# ----------------------------------------------------------------- helpers
def _connected_supplier(
    db: Session, vendor: Vendor, supplier_id: uuid.UUID
) -> Supplier:
    """Resolve a supplier the vendor actually trades with, or refuse.

    Taking the supplier from the body is fine; trusting that the vendor may
    transact with it is not. This is the check that makes the difference.
    """
    link = db.scalar(
        select(VendorDistributor).where(
            VendorDistributor.vendor_id == vendor.id,
            VendorDistributor.supplier_id == supplier_id,
            VendorDistributor.status == "active",
        )
    )
    if link is None:
        raise HTTPException(
            status_code=403, detail="You are not connected to this distributor"
        )

    supplier = db.get(Supplier, supplier_id)
    if supplier is None:
        raise HTTPException(status_code=404, detail="Distributor not found")
    return supplier


def _owned_order(db: Session, vendor: Vendor, order_id: uuid.UUID) -> PurchaseOrder:
    order = db.scalar(
        select(PurchaseOrder).where(
            PurchaseOrder.id == order_id, PurchaseOrder.vendor_id == vendor.id
        )
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return order


def order_out(db: Session, order: PurchaseOrder, *, detail: bool = False) -> OrderOut:
    supplier = db.get(Supplier, order.supplier_id)
    vendor = db.get(Vendor, order.vendor_id)

    return OrderOut(
        id=order.id,
        code=order.code,
        status=order.status,
        vendor_id=order.vendor_id,
        vendor_name=vendor.store_name if vendor else "Unknown",
        supplier_id=order.supplier_id,
        supplier_name=supplier.name if supplier else "Unknown",
        supplier_phone=supplier.phone if supplier else None,
        placed_at=order.placed_at,
        expected_at=order.expected_at,
        delivered_at=order.delivered_at,
        payment_terms_days=order.payment_terms_days,
        amount_total=order.amount_total,
        amount_paid=order.amount_paid,
        amount_due=order.amount_due,
        line_count=len(order.lines),
        note=order.note,
        pool_id=order.pool_id,
        lines=[OrderLineOut.model_validate(line) for line in order.lines]
        if detail
        else [],
        events=[OrderEventOut.model_validate(e) for e in order.events]
        if detail
        else [],
    )


# ----------------------------------------------------------- distributors
@router.get("/distributors", response_model=list[SupplierCardOut])
def list_distributors(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    category: str | None = None,
    near: bool = Query(True, description="Sort by distance from the shop"),
):
    """Wholesalers a shop could trade with, nearest first.

    Distance leads because a kirana owner's real constraint is who can
    actually reach them today, not who is theoretically cheapest.
    """
    suppliers = db.scalars(select(Supplier)).all()

    connected = {
        link.supplier_id: link
        for link in db.scalars(
            select(VendorDistributor).where(
                VendorDistributor.vendor_id == vendor.id,
                VendorDistributor.status == "active",
            )
        )
    }

    counts = dict(
        db.execute(
            select(CatalogEntry.supplier_id, func.count(CatalogEntry.id))
            .where(CatalogEntry.active.is_(True))
            .group_by(CatalogEntry.supplier_id)
        ).all()
    )

    cards: list[SupplierCardOut] = []
    for supplier in suppliers:
        if category and category not in (supplier.categories or []):
            continue

        distance = None
        if vendor.lat is not None and vendor.lon is not None:
            distance = round(
                haversine_km(vendor.lat, vendor.lon, supplier.lat, supplier.lon), 2
            )

        cards.append(
            SupplierCardOut(
                id=supplier.id,
                name=supplier.name,
                kind=supplier.kind,
                locality=supplier.locality,
                city=supplier.city,
                categories=list(supplier.categories or []),
                lead_days=supplier.lead_days,
                min_order_value=supplier.min_order_value,
                rating=supplier.rating,
                phone=supplier.phone,
                distance_km=distance,
                catalog_size=counts.get(supplier.id, 0),
                connected=supplier.id in connected,
                fill_rate=fill_rate(db, supplier.id),
            )
        )

    if near:
        cards.sort(key=lambda c: (c.distance_km is None, c.distance_km or 0))
    else:
        cards.sort(key=lambda c: -c.rating)
    return cards


@router.get("/connections", response_model=list[ConnectionOut])
def list_connections(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    links = db.scalars(
        select(VendorDistributor).where(
            VendorDistributor.vendor_id == vendor.id,
            VendorDistributor.status == "active",
        )
    ).all()

    out: list[ConnectionOut] = []
    for link in links:
        supplier = db.get(Supplier, link.supplier_id)
        if supplier is None:
            continue

        balance = sum(
            -e.amount if e.kind == "payment" else e.amount
            for e in db.scalars(
                select(LedgerEntry).where(
                    LedgerEntry.vendor_id == vendor.id,
                    LedgerEntry.supplier_id == link.supplier_id,
                )
            )
        )
        open_count = db.scalar(
            select(func.count(PurchaseOrder.id)).where(
                PurchaseOrder.vendor_id == vendor.id,
                PurchaseOrder.supplier_id == link.supplier_id,
                PurchaseOrder.status.in_(("placed", "confirmed", "dispatched")),
            )
        )

        out.append(
            ConnectionOut(
                supplier_id=link.supplier_id,
                supplier_name=supplier.name,
                locality=supplier.locality,
                status=link.status,
                shares_demand=link.shares_demand,
                scope_categories=list(link.scope_categories or []),
                credit_terms_days=link.credit_terms_days,
                credit_limit=link.credit_limit,
                connected_at=link.connected_at,
                outstanding=round(balance, 2),
                open_orders=open_count or 0,
                fill_rate=fill_rate(db, link.supplier_id, vendor_id=vendor.id),
            )
        )
    return out


@router.post("/distributors/{supplier_id}/connect", response_model=ConnectionOut)
def connect_distributor(
    supplier_id: uuid.UUID,
    body: ConnectIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    supplier = db.get(Supplier, supplier_id)
    if supplier is None:
        raise HTTPException(status_code=404, detail="Distributor not found")

    link = connect(
        db,
        vendor=vendor,
        supplier=supplier,
        shares_demand=body.shares_demand,
        credit_terms_days=body.credit_terms_days,
    )
    db.commit()

    return ConnectionOut(
        supplier_id=link.supplier_id,
        supplier_name=supplier.name,
        locality=supplier.locality,
        status=link.status,
        shares_demand=link.shares_demand,
        scope_categories=list(link.scope_categories or []),
        credit_terms_days=link.credit_terms_days,
        credit_limit=link.credit_limit,
        connected_at=link.connected_at,
    )


@router.delete("/distributors/{supplier_id}/connect", status_code=204)
def disconnect_distributor(
    supplier_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    try:
        disconnect(db, vendor=vendor, supplier_id=supplier_id)
    except ConnectionError_ as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    db.commit()


# --------------------------------------------------------------- sourcing
@router.get("/sourcing/{item_id}", response_model=SourcingOut)
def sourcing(
    item_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Who to buy this from, and why.

    The shortfall is measured against the item's own dynamic reorder point
    plus a week of cover, so the answer is "enough to stop worrying about it"
    rather than "exactly back to the trigger", which would put the shop back
    on the threshold the next morning.
    """
    item = db.scalar(
        select(InventoryItem).where(
            InventoryItem.id == item_id, InventoryItem.vendor_id == vendor.id
        )
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Item not found")

    rate = daily_rate(db, item.id)
    cover = days_of_cover(item.current_qty, rate)

    target = max(item.reorder_point, 0) + rate * 7
    shortfall = max(0.0, target - item.current_qty)
    if shortfall <= 0:
        # Not low, but the vendor asked — quote a week of demand so the screen
        # has something actionable rather than an empty state.
        shortfall = max(rate * 7, 1.0)

    options = rank_options(
        db, vendor=vendor, item=item, shortfall=shortfall, cover_days=cover
    )

    unconnected = db.scalar(
        select(func.count(func.distinct(CatalogEntry.supplier_id))).where(
            CatalogEntry.active.is_(True),
            func.lower(CatalogEntry.sku_name) == item.sku_name.lower(),
            CatalogEntry.supplier_id.notin_(
                select(VendorDistributor.supplier_id).where(
                    VendorDistributor.vendor_id == vendor.id,
                    VendorDistributor.status == "active",
                )
            ),
        )
    )

    return SourcingOut(
        item_id=item.id,
        sku_name=item.sku_name,
        unit=item.unit,
        current_qty=item.current_qty,
        reorder_point=item.reorder_point,
        shortfall=round(shortfall, 2),
        days_of_cover=cover,
        unconnected_count=unconnected or 0,
        options=[
            SourcingOptionOut(
                supplier_id=o.supplier.id,
                supplier_name=o.supplier.name,
                catalog_entry_id=o.entry.id,
                sku_name=o.entry.sku_name,
                unit=o.entry.unit,
                pack_size=o.entry.pack_size,
                pack_price=o.entry.pack_price,
                unit_price=round(o.entry.unit_price, 2),
                moq_packs=o.entry.moq_packs,
                packs_needed=o.plan.packs,
                qty_supplied=o.plan.qty_supplied,
                landed_cost=round(o.plan.cost, 2),
                lead_days=o.lead_days,
                arrives_in_time=o.arrives_in_time,
                fill_rate=o.fill,
                distance_km=o.distance_km,
                score=o.score,
                reasons=o.reasons,
            )
            for o in options
        ],
    )


# ----------------------------------------------------------------- orders
@router.post("/orders", response_model=OrderOut, status_code=201)
def create_order(
    body: OrderCreateIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Create an order, idempotently.

    A device that placed this order offline replays it with the same
    `client_event_id`. Returning the existing order rather than a conflict is
    what makes the retry safe: the app cannot tell whether the first attempt
    reached the server, so the server has to make asking twice harmless.
    """
    if body.client_event_id is not None:
        existing = db.scalar(
            select(PurchaseOrder).where(
                PurchaseOrder.client_event_id == body.client_event_id
            )
        )
        if existing is not None:
            if existing.vendor_id != vendor.id:
                raise HTTPException(status_code=409, detail="Event id already used")
            return order_out(db, existing, detail=True)

    supplier = _connected_supplier(db, vendor, body.supplier_id)

    try:
        order = build_order(
            db,
            vendor=vendor,
            supplier=supplier,
            lines=[line.model_dump() for line in body.lines],
            note=body.note,
            pool_id=body.pool_id,
            client_event_id=body.client_event_id,
        )
        if body.place_immediately:
            transition(db, order, "placed", actor_role="vendor", actor_id=vendor.id)
    except OrderError as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    db.commit()
    return order_out(db, order, detail=True)


@router.get("/orders", response_model=list[OrderOut])
def list_orders(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    status: str | None = Query(None, description="Filter by status"),
    open_only: bool = False,
):
    stmt = select(PurchaseOrder).where(PurchaseOrder.vendor_id == vendor.id)
    if status:
        stmt = stmt.where(PurchaseOrder.status == status)
    if open_only:
        stmt = stmt.where(PurchaseOrder.status.notin_(("delivered", "cancelled")))

    orders = db.scalars(stmt.order_by(PurchaseOrder.created_at.desc())).all()
    return [order_out(db, o) for o in orders]


@router.get("/orders/{order_id}", response_model=OrderOut)
def get_order(
    order_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    return order_out(db, _owned_order(db, vendor, order_id), detail=True)


@router.post("/orders/{order_id}/place", response_model=OrderOut)
def place_order(
    order_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    order = _owned_order(db, vendor, order_id)
    try:
        transition(db, order, "placed", actor_role="vendor", actor_id=vendor.id)
    except OrderError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    db.commit()
    return order_out(db, order, detail=True)


@router.post("/orders/{order_id}/cancel", response_model=OrderOut)
def cancel_order(
    order_id: uuid.UUID,
    body: OrderCancelIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    order = _owned_order(db, vendor, order_id)
    try:
        transition(
            db,
            order,
            "cancelled",
            actor_role="vendor",
            actor_id=vendor.id,
            note=body.reason,
        )
    except OrderError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    db.commit()
    return order_out(db, order, detail=True)


@router.post("/orders/{order_id}/receive", response_model=OrderOut)
def receive_order(
    order_id: uuid.UUID,
    body: OrderFulfilIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Confirm what actually arrived, and put it on the shelf.

    The vendor's count wins over the distributor's, because the vendor is the
    one standing in front of the crates. A short delivery recorded here is
    what feeds the fill rate that later ranks this supplier down.
    """
    order = _owned_order(db, vendor, order_id)

    if order.delivered_at is not None:
        # Already received. Idempotent rather than an error: a flaky connection
        # should not make a vendor wonder whether their stock was counted.
        return order_out(db, order, detail=True)

    try:
        if body.lines:
            amend_lines(
                order,
                {line.line_id: line.packs for line in body.lines},
                "packs_delivered",
            )
        else:
            amend_lines(order, {}, "packs_delivered")

        transition(
            db,
            order,
            "delivered",
            actor_role="vendor",
            actor_id=vendor.id,
            note=body.note,
        )
        apply_delivery(db, order)
    except OrderError as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    db.commit()
    return order_out(db, order, detail=True)


# ----------------------------------------------------------------- ledger
@router.get("/ledger", response_model=LedgerOut)
def ledger(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    entries = db.scalars(
        select(LedgerEntry)
        .where(LedgerEntry.vendor_id == vendor.id)
        .order_by(LedgerEntry.created_at.desc())
    ).all()

    summary = summarise_ledger(list(entries))

    lines = [
        LedgerLineOut(
            id=entry.id,
            kind=entry.kind,
            amount=entry.amount,
            order_code=(
                order.code
                if (order := db.get(PurchaseOrder, entry.order_id) if entry.order_id else None)
                else None
            ),
            counterparty=(
                supplier.name
                if (supplier := db.get(Supplier, entry.supplier_id))
                else "Unknown"
            ),
            due_on=entry.due_on,
            overdue=entry.id in summary.overdue_ids,
            note=entry.note,
            created_at=entry.created_at,
        )
        for entry in entries
    ]

    return LedgerOut(
        outstanding=summary.outstanding,
        overdue=summary.overdue,
        due_this_week=summary.due_this_week,
        entries=lines,
    )
