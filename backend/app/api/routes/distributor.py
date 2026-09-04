"""The wholesaler's side of the marketplace, everything under `/dist`.

Every handler takes its `supplier_id` from `user.supplier_id` — resolved from
the bearer token — and never from the request body or a path parameter. That
single discipline is what stops one distributor reading another's order book,
and it is the reason `_owned_order` below takes the user rather than an id.
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ...core.db import get_db, utcnow
from ...core.security import current_distributor
from ...models import (
    BargainPool,
    CatalogEntry,
    DistributorUser,
    LedgerEntry,
    PoolMember,
    PurchaseOrder,
    Supplier,
    Vendor,
    VendorDistributor,
)
from ...schemas import (
    AtRiskShopOut,
    BulkConfirmOut,
    CatalogEntryIn,
    CatalogEntryOut,
    CatalogEntryUpdate,
    DeadLineOut,
    DemandLineOut,
    DispatchLegOut,
    DispatchOut,
    DispatchStopOut,
    DemandOut,
    DistributorSummaryOut,
    DistributorVendorOut,
    LedgerLineOut,
    LedgerOut,
    OrderCancelIn,
    OrderFulfilIn,
    OrderOut,
    PaymentIn,
    PoolOut,
    PoolQuoteIn,
    PriceListImportIn,
    PriceListPreviewOut,
    PriceListRowOut,
)
from ...services.distributor_intel import (
    at_risk_shops,
    book_summary,
    dead_lines,
    demand_outlook,
)
from ...services.onboarding import commit_price_list, parse_price_list
from ...services.ordering import (
    OrderError,
    amend_lines,
    summarise_ledger,
    transition,
)
from .orders import order_out

router = APIRouter(prefix="/dist", tags=["distributor"])


# ----------------------------------------------------------------- helpers
def _supplier(db: Session, user: DistributorUser) -> Supplier:
    supplier = db.get(Supplier, user.supplier_id)
    if supplier is None:
        raise HTTPException(status_code=404, detail="Business not found")
    return supplier


def _owned_order(
    db: Session, user: DistributorUser, order_id: uuid.UUID
) -> PurchaseOrder:
    order = db.scalar(
        select(PurchaseOrder).where(
            PurchaseOrder.id == order_id,
            PurchaseOrder.supplier_id == user.supplier_id,
        )
    )
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return order


def _owned_entry(
    db: Session, user: DistributorUser, entry_id: uuid.UUID
) -> CatalogEntry:
    entry = db.scalar(
        select(CatalogEntry).where(
            CatalogEntry.id == entry_id,
            CatalogEntry.supplier_id == user.supplier_id,
        )
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Catalogue item not found")
    return entry


# ---------------------------------------------------------------- summary
@router.get("/summary", response_model=DistributorSummaryOut)
def summary(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """The Today screen: what needs doing, and the one thing worth doing first."""
    supplier = _supplier(db, user)

    orders = db.scalars(
        select(PurchaseOrder).where(PurchaseOrder.supplier_id == supplier.id)
    ).all()

    needs_action = sum(1 for o in orders if o.status == "placed")
    to_dispatch = sum(1 for o in orders if o.status == "confirmed")
    in_transit = sum(1 for o in orders if o.status == "dispatched")

    week_ago = utcnow().timestamp() - 7 * 86400
    delivered_week = [
        o
        for o in orders
        if o.status == "delivered"
        and o.delivered_at
        and o.delivered_at.timestamp() >= week_ago
    ]

    by_vendor: dict[uuid.UUID, list[LedgerEntry]] = {}
    for entry in db.scalars(
        select(LedgerEntry).where(LedgerEntry.supplier_id == supplier.id)
    ):
        by_vendor.setdefault(entry.vendor_id, []).append(entry)

    per_shop = [summarise_ledger(rows) for rows in by_vendor.values()]
    outstanding = sum(s.outstanding for s in per_shop)
    overdue = sum(s.overdue for s in per_shop)

    connected = db.scalar(
        select(func.count(VendorDistributor.id)).where(
            VendorDistributor.supplier_id == supplier.id,
            VendorDistributor.status == "active",
        )
    )

    at_risk = at_risk_shops(db, supplier)
    open_pools = _matching_pools(db, supplier)

    prompt, detail = _top_prompt(needs_action, at_risk, overdue, open_pools)

    return DistributorSummaryOut(
        business_name=supplier.name,
        needs_action=needs_action,
        to_dispatch=to_dispatch,
        in_transit=in_transit,
        delivered_this_week=len(delivered_week),
        revenue_this_week=round(sum(o.amount_total for o in delivered_week), 2),
        outstanding=round(outstanding, 2),
        overdue=round(overdue, 2),
        connected_shops=connected or 0,
        at_risk_count=len(at_risk),
        open_pool_count=len(open_pools),
        top_prompt=prompt,
        top_prompt_detail=detail,
    )


def _top_prompt(
    needs_action: int, at_risk: list, overdue: float, pools: list
) -> tuple[str | None, str | None]:
    """The single most useful next action, chosen by what it is worth.

    Ordered by urgency to the *relationship*, not by size: an unanswered order
    is a shop waiting on you, which costs more than a stale receivable.
    """
    if needs_action:
        return (
            f"{needs_action} order{'s' if needs_action > 1 else ''} waiting",
            "A shop is waiting to hear whether you can supply.",
        )
    if at_risk:
        top = at_risk[0]
        return (
            f"{top.vendor.store_name} runs out of {top.item.sku_name} "
            f"in {top.cover:.0f} day{'s' if top.cover >= 2 else ''}",
            f"Your lead time is {top.lead_days} day"
            f"{'s' if top.lead_days != 1 else ''} — worth a call now. "
            f"About ₹{top.est_value:,.0f}.",
        )
    if pools:
        return (
            f"{len(pools)} group order{'s' if len(pools) > 1 else ''} open nearby",
            "Several shops need the same thing. Quote once, supply all of them.",
        )
    if overdue > 0:
        return (
            f"₹{overdue:,.0f} overdue",
            "Payments past their agreed terms.",
        )
    return None, None


# ----------------------------------------------------------------- orders
@router.get("/orders", response_model=list[OrderOut])
def inbox(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
    status: str | None = Query(None),
    open_only: bool = False,
):
    stmt = select(PurchaseOrder).where(
        PurchaseOrder.supplier_id == user.supplier_id,
        # A draft is a shop still deciding. Showing it would be reading over
        # their shoulder, and answering it would be worse.
        PurchaseOrder.status != "draft",
    )
    if status:
        stmt = stmt.where(PurchaseOrder.status == status)
    if open_only:
        stmt = stmt.where(PurchaseOrder.status.notin_(("delivered", "cancelled")))

    orders = db.scalars(stmt.order_by(PurchaseOrder.placed_at.desc())).all()
    return [order_out(db, o) for o in orders]


@router.get("/orders/{order_id}", response_model=OrderOut)
def order_detail(
    order_id: uuid.UUID,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    return order_out(db, _owned_order(db, user, order_id), detail=True)


def _fulfil(
    db: Session,
    user: DistributorUser,
    order_id: uuid.UUID,
    body: OrderFulfilIn,
    to_status: str,
    field: str | None,
) -> OrderOut:
    order = _owned_order(db, user, order_id)
    try:
        if field:
            amend_lines(
                order,
                {line.line_id: line.packs for line in (body.lines or [])},
                field,
            )
        transition(
            db,
            order,
            to_status,
            actor_role="distributor",
            actor_id=user.id,
            note=body.note,
        )
    except OrderError as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    db.commit()
    return order_out(db, order, detail=True)


@router.post("/orders/{order_id}/confirm", response_model=OrderOut)
def confirm(
    order_id: uuid.UUID,
    body: OrderFulfilIn,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Accept an order, optionally for less than was asked.

    Part-filling here rather than silently shipping short is the honest move:
    the shop learns now, while they can still source the rest elsewhere.
    """
    return _fulfil(db, user, order_id, body, "confirmed", "packs_confirmed")


@router.post("/orders/{order_id}/dispatch", response_model=OrderOut)
def dispatch(
    order_id: uuid.UUID,
    body: OrderFulfilIn,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    return _fulfil(db, user, order_id, body, "dispatched", None)


@router.post("/orders/{order_id}/deliver", response_model=OrderOut)
def deliver(
    order_id: uuid.UUID,
    body: OrderFulfilIn,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Mark as delivered from the distributor's side.

    Deliberately does *not* restock the shop's inventory. The vendor's
    `/orders/{id}/receive` does that, because the count that goes on the shelf
    should be the one made by the person standing in front of the crates.
    """
    return _fulfil(db, user, order_id, body, "delivered", "packs_delivered")


@router.post("/orders/{order_id}/reject", response_model=OrderOut)
def reject(
    order_id: uuid.UUID,
    body: OrderCancelIn,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    order = _owned_order(db, user, order_id)
    try:
        transition(
            db,
            order,
            "cancelled",
            actor_role="distributor",
            actor_id=user.id,
            note=body.reason or "Declined by distributor",
        )
    except OrderError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    db.commit()
    return order_out(db, order, detail=True)


@router.post("/orders/bulk-confirm", response_model=BulkConfirmOut)
def bulk_confirm(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Accept every waiting order in full, at once.

    A wholesaler who can supply everything asked for should not have to open
    twelve screens to say so. Confirms in full only -- anything needing a
    part-fill is left alone, because the whole value of a part-fill is that it
    was a decision, and a bulk action cannot make it.
    """
    waiting = db.scalars(
        select(PurchaseOrder).where(
            PurchaseOrder.supplier_id == user.supplier_id,
            PurchaseOrder.status == "placed",
        )
    ).all()

    confirmed: list[str] = []
    failed = 0

    for order in waiting:
        try:
            amend_lines(order, {}, "packs_confirmed")
            transition(
                db, order, "confirmed",
                actor_role="distributor", actor_id=user.id,
                note="Accepted in full",
            )
            confirmed.append(order.code)
        except OrderError:
            # One bad order must not sink the batch. It stays waiting, which
            # is the honest outcome -- the wholesaler will see it still there.
            failed += 1

    db.commit()
    return BulkConfirmOut(
        confirmed=len(confirmed), failed=failed, order_codes=confirmed
    )


@router.get("/dispatch", response_model=DispatchOut)
def dispatch_sheet(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Today's round, grouped by locality.

    A flat list of confirmed orders is a to-do list; grouped by area it is a
    route. Money owed rides along on each stop because collecting on delivery
    is how this trade actually settles, and a driver who does not know what to
    ask for does not ask.
    """
    orders = db.scalars(
        select(PurchaseOrder).where(
            PurchaseOrder.supplier_id == user.supplier_id,
            PurchaseOrder.status.in_(("confirmed", "dispatched")),
        )
    ).all()

    now = utcnow()
    legs: dict[str, list[DispatchStopOut]] = {}

    for order in orders:
        vendor = db.get(Vendor, order.vendor_id)
        if vendor is None:
            continue

        legs.setdefault(vendor.locality or "Unassigned", []).append(
            DispatchStopOut(
                order_id=order.id,
                order_code=order.code,
                vendor_id=vendor.id,
                store_name=vendor.store_name,
                phone=vendor.phone,
                line_count=len(order.lines),
                amount_total=order.amount_total,
                amount_due=order.amount_due,
                expected_at=order.expected_at,
                overdue=order.expected_at is not None and order.expected_at < now,
            )
        )

    built = [
        DispatchLegOut(
            locality=locality,
            # Late stops first within a leg: the van is already in the area,
            # and the only ordering that matters is who has waited longest.
            stops=sorted(stops, key=lambda s: (not s.overdue, s.expected_at or now)),
            total_value=round(sum(s.amount_total for s in stops), 2),
            to_collect=round(sum(s.amount_due for s in stops), 2),
        )
        for locality, stops in legs.items()
    ]
    # Densest area first — the most deliveries per kilometre driven.
    built.sort(key=lambda leg: -len(leg.stops))

    return DispatchOut(
        legs=built,
        stop_count=sum(len(leg.stops) for leg in built),
        total_value=round(sum(leg.total_value for leg in built), 2),
        to_collect=round(sum(leg.to_collect for leg in built), 2),
    )


# ---------------------------------------------------------------- catalog
@router.get("/catalog", response_model=list[CatalogEntryOut])
def catalog(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
    include_inactive: bool = False,
):
    stmt = select(CatalogEntry).where(CatalogEntry.supplier_id == user.supplier_id)
    if not include_inactive:
        stmt = stmt.where(CatalogEntry.active.is_(True))

    entries = db.scalars(stmt.order_by(CatalogEntry.sku_name)).all()
    return [_entry_out(e) for e in entries]


def _entry_out(entry: CatalogEntry) -> CatalogEntryOut:
    return CatalogEntryOut(
        id=entry.id,
        supplier_id=entry.supplier_id,
        sku_name=entry.sku_name,
        category=entry.category,
        unit=entry.unit,
        pack_size=entry.pack_size,
        pack_price=entry.pack_price,
        unit_price=round(entry.unit_price, 2),
        moq_packs=entry.moq_packs,
        lead_days=entry.lead_days,
        available_packs=entry.available_packs,
        active=entry.active,
    )


@router.post("/catalog", response_model=CatalogEntryOut, status_code=201)
def add_catalog_entry(
    body: CatalogEntryIn,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    existing = db.scalar(
        select(CatalogEntry).where(
            CatalogEntry.supplier_id == user.supplier_id,
            func.lower(CatalogEntry.sku_name) == body.sku_name.lower(),
        )
    )
    if existing is not None:
        raise HTTPException(
            status_code=409, detail=f"{body.sku_name} is already in your catalogue"
        )

    entry = CatalogEntry(supplier_id=user.supplier_id, **body.model_dump())
    db.add(entry)
    _sync_supplier_categories(db, user.supplier_id)
    db.commit()
    return _entry_out(entry)


@router.patch("/catalog/{entry_id}", response_model=CatalogEntryOut)
def update_catalog_entry(
    entry_id: uuid.UUID,
    body: CatalogEntryUpdate,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    entry = _owned_entry(db, user, entry_id)
    for key, value in body.model_dump(exclude_none=True).items():
        setattr(entry, key, value)
    _sync_supplier_categories(db, user.supplier_id)
    db.commit()
    return _entry_out(entry)


@router.delete("/catalog/{entry_id}", status_code=204)
def withdraw_catalog_entry(
    entry_id: uuid.UUID,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Soft delete, so historic order lines keep resolving to what they cost."""
    entry = _owned_entry(db, user, entry_id)
    entry.active = False
    _sync_supplier_categories(db, user.supplier_id)
    db.commit()


def _sync_supplier_categories(db: Session, supplier_id: uuid.UUID) -> None:
    """Keep the supplier's advertised aisles in step with what they actually list.

    Note this does *not* touch any `VendorDistributor.scope_categories`: those
    are frozen at grant time on purpose, and a catalogue edit must never widen
    what a distributor can see.
    """
    supplier = db.get(Supplier, supplier_id)
    if supplier is None:
        return
    db.flush()
    supplier.categories = sorted(
        set(
            db.scalars(
                select(CatalogEntry.category)
                .where(
                    CatalogEntry.supplier_id == supplier_id,
                    CatalogEntry.active.is_(True),
                )
                .distinct()
            ).all()
        )
    )


@router.post("/catalog/import", response_model=PriceListPreviewOut)
def import_price_list(
    body: PriceListImportIn,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Preview a pasted price list, and commit it only when asked.

    A half-applied import is worse than a rejected one — the distributor
    cannot tell which rows landed, and every order priced in between is wrong.
    """
    rows = parse_price_list(db, user.supplier_id, body.csv_text)

    if body.commit:
        commit_price_list(db, user.supplier_id, rows)
        _sync_supplier_categories(db, user.supplier_id)
        db.commit()

    return PriceListPreviewOut(
        rows=[
            PriceListRowOut(
                row=r.row,
                sku_name=r.sku_name,
                category=r.category,
                unit=r.unit,
                pack_size=r.pack_size,
                pack_price=r.pack_price,
                moq_packs=r.moq_packs,
                action=r.action,
                errors=r.errors,
            )
            for r in rows
        ],
        valid=sum(1 for r in rows if r.ok),
        invalid=sum(1 for r in rows if not r.ok),
        will_create=sum(1 for r in rows if r.ok and r.action == "create"),
        will_update=sum(1 for r in rows if r.ok and r.action == "update"),
    )


# ------------------------------------------------------------------ shops
@router.get("/vendors", response_model=list[DistributorVendorOut])
def vendors(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    supplier = _supplier(db, user)
    return [
        DistributorVendorOut(
            vendor_id=row.vendor.id,
            store_name=row.vendor.store_name,
            owner_name=row.vendor.name,
            locality=row.vendor.locality or "—",
            phone=row.vendor.phone,
            connected_at=row.connection.connected_at,
            order_count=row.order_count,
            delivered_count=row.delivered_count,
            revenue=row.revenue,
            outstanding=row.outstanding,
            fill_rate=row.fill,
            last_order_at=row.last_order_at,
            shares_demand=row.connection.shares_demand,
        )
        for row in book_summary(db, supplier)
    ]


# ----------------------------------------------------------------- demand
@router.get("/demand", response_model=DemandOut)
def demand(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
    horizon_days: int = Query(7, ge=1, le=30),
):
    """What the book will need, and who runs out before the van can reach them.

    Only shops that opted into demand sharing contribute, and only in the
    categories their consent covered when they granted it.
    """
    supplier = _supplier(db, user)
    outlook = demand_outlook(db, supplier, horizon_days=horizon_days)

    # A read that writes. `demand_outlook` fills the forecast cache as it goes,
    # and routes own the transaction here — without this the rows are flushed
    # and then discarded when the session closes, which is exactly what made
    # the cache look like it was not working at all.
    db.commit()

    return DemandOut(
        horizon_days=outlook.horizon_days,
        consenting_shops=outlook.consenting_shops,
        total_connected=outlook.total_connected,
        lines=[
            DemandLineOut(
                sku_name=line.sku_name,
                category=line.category,
                unit=line.unit,
                expected_qty=line.expected_qty,
                shop_count=line.shop_count,
                catalog_entry_id=line.entry.id if line.entry else None,
                packs_to_stock=line.packs_to_stock,
                est_revenue=line.est_revenue,
                confidence=line.confidence,
            )
            for line in outlook.lines
        ],
        at_risk=[
            AtRiskShopOut(
                vendor_id=row.vendor.id,
                store_name=row.vendor.store_name,
                locality=row.vendor.locality or "—",
                sku_name=row.item.sku_name,
                unit=row.item.unit,
                current_qty=row.item.current_qty,
                daily_rate=row.rate,
                days_of_cover=row.cover,
                lead_days=row.lead_days,
                shortfall_by_arrival=row.shortfall_by_arrival,
                suggested_packs=row.suggested_packs,
                est_value=row.est_value,
            )
            for row in outlook.at_risk
        ],
        dead_lines=[
            DeadLineOut(
                catalog_entry_id=row.entry.id,
                sku_name=row.entry.sku_name,
                category=row.entry.category,
                days_since_last_order=row.days_since_last_order,
                pack_price=row.entry.pack_price,
            )
            for row in outlook.dead_lines
        ],
    )


# ------------------------------------------------------------------ pools
def _matching_pools(db: Session, supplier: Supplier) -> list[BargainPool]:
    """Open group orders for something this distributor actually sells."""
    listed = {
        name.lower()
        for name in db.scalars(
            select(CatalogEntry.sku_name).where(
                CatalogEntry.supplier_id == supplier.id,
                CatalogEntry.active.is_(True),
            )
        )
    }
    if not listed:
        return []

    pools = db.scalars(
        select(BargainPool).where(BargainPool.status == "open")
    ).all()
    return [p for p in pools if p.sku_name.lower() in listed]


@router.get("/pools", response_model=list[PoolOut])
def pools(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Group orders this distributor could win.

    Until now `BargainPool.supplier_id` was always null: the engine computed a
    bulk discount with nobody on the other side of it. This endpoint and the
    quote below are that missing counterparty.
    """
    supplier = _supplier(db, user)
    return [PoolOut.model_validate(p) for p in _matching_pools(db, supplier)]


@router.post("/pools/{pool_id}/quote", response_model=PoolOut)
def quote_pool(
    pool_id: uuid.UUID,
    body: PoolQuoteIn,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Claim a pool by beating its indicative bulk price."""
    pool = db.get(BargainPool, pool_id)
    if pool is None:
        raise HTTPException(status_code=404, detail="Group order not found")
    if pool.status != "open":
        raise HTTPException(status_code=400, detail="This group order has closed")

    if body.bulk_unit_price >= pool.base_unit_price:
        raise HTTPException(
            status_code=400,
            detail=(
                f"A quote has to beat the going rate of "
                f"₹{pool.base_unit_price:.2f}."
            ),
        )

    pool.supplier_id = user.supplier_id
    pool.bulk_unit_price = body.bulk_unit_price
    db.commit()
    return PoolOut.model_validate(pool)


# ----------------------------------------------------------------- ledger
@router.get("/ledger", response_model=LedgerOut)
def receivables(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    entries = db.scalars(
        select(LedgerEntry)
        .where(LedgerEntry.supplier_id == user.supplier_id)
        .order_by(LedgerEntry.created_at.desc())
    ).all()

    # Netted per shop: one customer's overpayment must not be allowed to mask
    # another's arrears, which a single pooled calculation would do.
    by_vendor: dict[uuid.UUID, list[LedgerEntry]] = {}
    for entry in entries:
        by_vendor.setdefault(entry.vendor_id, []).append(entry)

    summaries = {vid: summarise_ledger(rows) for vid, rows in by_vendor.items()}
    overdue_ids = {i for s in summaries.values() for i in s.overdue_ids}

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
                vendor.store_name
                if (vendor := db.get(Vendor, entry.vendor_id))
                else "Unknown"
            ),
            due_on=entry.due_on,
            overdue=entry.id in overdue_ids,
            note=entry.note,
            created_at=entry.created_at,
        )
        for entry in entries
    ]

    return LedgerOut(
        outstanding=round(sum(s.outstanding for s in summaries.values()), 2),
        overdue=round(sum(s.overdue for s in summaries.values()), 2),
        due_this_week=round(sum(s.due_this_week for s in summaries.values()), 2),
        entries=lines,
    )


@router.post("/payments", status_code=201)
def record_payment(
    body: PaymentIn,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    """Log money received. No gateway — this is the digital khata, not a rail."""
    link = db.scalar(
        select(VendorDistributor).where(
            VendorDistributor.vendor_id == body.vendor_id,
            VendorDistributor.supplier_id == user.supplier_id,
        )
    )
    if link is None:
        raise HTTPException(status_code=404, detail="That shop is not on your book")

    entry = LedgerEntry(
        vendor_id=body.vendor_id,
        supplier_id=user.supplier_id,
        order_id=body.order_id,
        kind="payment",
        amount=body.amount,
        note=body.note or "Payment received",
    )
    db.add(entry)

    if body.order_id:
        order = db.get(PurchaseOrder, body.order_id)
        if order is not None and order.supplier_id == user.supplier_id:
            order.amount_paid = round(order.amount_paid + body.amount, 2)

    db.commit()
    return {"recorded": True, "amount": body.amount}
