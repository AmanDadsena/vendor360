"""What a distributor can know about the shops they supply.

The same forecasting engine that tells a shopkeeper what they will sell tells
a wholesaler what their book will need — pointed at forty shops instead of
one. That is the whole of the distributor's intelligence product, and it costs
almost nothing to build because the hard part already exists.

What it does cost is care about consent. Every query in this module passes
through `_consenting`, which filters to connections that are active, that
opted into demand sharing, and whose *frozen* category scope admits the SKU
being asked about. A distributor who adds `dairy` to their price list tomorrow
does not thereby acquire yesterday's shops' milk numbers.
"""
from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.db import utcnow
from ..models import (
    CatalogEntry,
    InventoryItem,
    LedgerEntry,
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
    Transaction,
    Vendor,
    VendorDistributor,
)
from . import forecast_cache
from .ordering import fill_rate
from .sourcing import daily_rate, days_of_cover, plan_packs

# Aggregating a handful of shops would let a distributor read one shop's
# numbers off a "total". The heatmap already draws this line at three; the
# same threshold applies here for the same reason.
MIN_SHOPS_FOR_AGGREGATE = 3

DEAD_LINE_DAYS = 30


@dataclass
class DemandLine:
    sku_name: str
    category: str
    unit: str
    expected_qty: float
    shop_count: int
    entry: CatalogEntry | None = None
    confidence: str = "medium"

    @property
    def packs_to_stock(self) -> float | None:
        if self.entry is None:
            return None
        return plan_packs(
            self.expected_qty, self.entry.pack_size, self.entry.pack_price
        ).packs

    @property
    def est_revenue(self) -> float:
        if self.entry is None:
            return 0.0
        return round(self.expected_qty * self.entry.unit_price, 2)


@dataclass
class AtRiskShop:
    vendor: Vendor
    item: InventoryItem
    rate: float
    cover: float
    lead_days: int
    entry: CatalogEntry | None

    @property
    def shortfall_by_arrival(self) -> float:
        """How deep in the hole the shop is by the time a delivery lands."""
        return round(max(0.0, self.rate * self.lead_days - self.item.current_qty), 2)

    @property
    def suggested_packs(self) -> float:
        if self.entry is None or self.shortfall_by_arrival <= 0:
            return 0.0
        # A week of cover past the gap, so the call is worth making.
        target = self.shortfall_by_arrival + self.rate * 7
        return plan_packs(
            target, self.entry.pack_size, self.entry.pack_price, self.entry.moq_packs
        ).packs

    @property
    def est_value(self) -> float:
        if self.entry is None:
            return 0.0
        return round(self.suggested_packs * self.entry.pack_price, 2)


@dataclass
class BookRow:
    vendor: Vendor
    connection: VendorDistributor
    order_count: int = 0
    delivered_count: int = 0
    revenue: float = 0.0
    outstanding: float = 0.0
    fill: float | None = None
    last_order_at: object | None = None


@dataclass
class DeadLine:
    entry: CatalogEntry
    days_since_last_order: int | None


@dataclass
class Outlook:
    horizon_days: int
    consenting_shops: int
    total_connected: int
    lines: list[DemandLine] = field(default_factory=list)
    at_risk: list[AtRiskShop] = field(default_factory=list)
    dead_lines: list[DeadLine] = field(default_factory=list)


# ------------------------------------------------------------------ consent
def _connections(db: Session, supplier_id: uuid.UUID) -> list[VendorDistributor]:
    return list(
        db.scalars(
            select(VendorDistributor).where(
                VendorDistributor.supplier_id == supplier_id,
                VendorDistributor.status == "active",
            )
        )
    )


def _consenting(
    connections: list[VendorDistributor], category: str
) -> dict[uuid.UUID, VendorDistributor]:
    """The connections that permit this distributor to see this category.

    Three conditions, all of which must hold: the relationship is live, the
    vendor opted into demand sharing, and the category falls inside the scope
    frozen when they opted in.
    """
    return {c.vendor_id: c for c in connections if c.covers(category)}


def catalog_by_name(
    db: Session, supplier_id: uuid.UUID
) -> dict[str, CatalogEntry]:
    entries = db.scalars(
        select(CatalogEntry).where(
            CatalogEntry.supplier_id == supplier_id,
            CatalogEntry.active.is_(True),
        )
    ).all()
    return {e.sku_name.lower(): e for e in entries}


# ------------------------------------------------------------------ demand
def demand_outlook(
    db: Session,
    supplier: Supplier,
    *,
    horizon_days: int = 7,
    today: date | None = None,
) -> Outlook:
    """Aggregate expected demand across the shops that consent to share it.

    Runs the real forecaster per item rather than extrapolating past orders,
    because past orders only show what the shop managed to buy — not what they
    were about to need and could not get.
    """
    today = today or date.today()
    connections = _connections(db, supplier.id)
    listings = catalog_by_name(db, supplier.id)

    outlook = Outlook(
        horizon_days=horizon_days,
        consenting_shops=0,
        total_connected=len(connections),
    )
    if not connections or not listings:
        return outlook

    buckets: dict[str, dict] = defaultdict(
        lambda: {"qty": 0.0, "shops": set(), "unit": "pc", "category": "staples"}
    )
    contributing: set[uuid.UUID] = set()

    for key, entry in listings.items():
        permitted = _consenting(connections, entry.category)
        if not permitted:
            continue

        items = db.scalars(
            select(InventoryItem).where(
                InventoryItem.vendor_id.in_(permitted.keys()),
                func.lower(InventoryItem.sku_name) == key,
            )
        ).all()

        for item in items:
            # Through the cache. Fitting a model per (shop x SKU) on every
            # request put this endpoint at ten seconds against a seeded book,
            # which is past the client's read timeout — so the screen fell
            # back to an empty outlook and told the wholesaler they had no
            # shops. A stale-by-a-day forecast is worth far more than that.
            predicted = forecast_cache.total_for(
                db,
                item,
                horizon_days=horizon_days,
                today=today,
                history=_history(db, item.id),
            )
            bucket = buckets[key]
            bucket["qty"] += predicted
            bucket["shops"].add(item.vendor_id)
            bucket["unit"] = item.unit
            bucket["category"] = item.category
            contributing.add(item.vendor_id)

    for key, bucket in buckets.items():
        shops = len(bucket["shops"])
        # Same k-anonymity rule the heatmap applies: below three contributors,
        # a "total" is one shop's numbers wearing a disguise.
        if shops < MIN_SHOPS_FOR_AGGREGATE:
            continue
        entry = listings.get(key)
        outlook.lines.append(
            DemandLine(
                sku_name=entry.sku_name if entry else key,
                category=bucket["category"],
                unit=bucket["unit"],
                expected_qty=round(bucket["qty"], 2),
                shop_count=shops,
                entry=entry,
                confidence="high" if shops >= 8 else "medium",
            )
        )

    outlook.lines.sort(key=lambda line: line.est_revenue, reverse=True)
    outlook.consenting_shops = len(contributing)
    outlook.at_risk = at_risk_shops(db, supplier, connections=connections)
    outlook.dead_lines = dead_lines(db, supplier)
    return outlook


def _history(db: Session, item_id: uuid.UUID, days: int = 120):
    since = utcnow() - timedelta(days=days)
    rows = db.execute(
        select(Transaction.occurred_at, Transaction.qty).where(
            Transaction.item_id == item_id,
            Transaction.type == "sale",
            Transaction.occurred_at >= since,
        )
    ).all()
    return [(occurred.date(), qty) for occurred, qty in rows]


# ----------------------------------------------------------------- at risk
def at_risk_shops(
    db: Session,
    supplier: Supplier,
    *,
    connections: list[VendorDistributor] | None = None,
    limit: int = 25,
) -> list[AtRiskShop]:
    """Shops that run out before this distributor's van can reach them.

    Not a report — a call list. The distributor's lead time is the thing that
    turns "low stock" into "low stock *and I am the one who can fix it, but
    only if I leave now*".
    """
    connections = connections if connections is not None else _connections(db, supplier.id)
    listings = catalog_by_name(db, supplier.id)
    if not connections or not listings:
        return []

    rows: list[AtRiskShop] = []

    for key, entry in listings.items():
        permitted = _consenting(connections, entry.category)
        if not permitted:
            continue

        lead = entry.lead_days if entry.lead_days is not None else supplier.lead_days

        results = db.execute(
            select(InventoryItem, Vendor)
            .join(Vendor, Vendor.id == InventoryItem.vendor_id)
            .where(
                InventoryItem.vendor_id.in_(permitted.keys()),
                func.lower(InventoryItem.sku_name) == key,
            )
        ).all()

        for item, vendor in results:
            rate = daily_rate(db, item.id)
            if rate <= 0:
                continue
            cover = days_of_cover(item.current_qty, rate)
            if cover is None or cover > lead:
                continue
            rows.append(
                AtRiskShop(
                    vendor=vendor,
                    item=item,
                    rate=rate,
                    cover=cover,
                    lead_days=lead,
                    entry=entry,
                )
            )

    # Most valuable call first: a shop about to lose ₹4,000 of sales outranks
    # one about to lose ₹80, even if the second runs out sooner.
    rows.sort(key=lambda r: r.est_value, reverse=True)
    return rows[:limit]


# -------------------------------------------------------------------- book
def book_summary(db: Session, supplier: Supplier) -> list[BookRow]:
    """Every connected shop, with what the relationship is actually worth."""
    connections = _connections(db, supplier.id)
    if not connections:
        return []

    vendors = {
        v.id: v
        for v in db.scalars(
            select(Vendor).where(Vendor.id.in_([c.vendor_id for c in connections]))
        )
    }

    rows: list[BookRow] = []
    for connection in connections:
        vendor = vendors.get(connection.vendor_id)
        if vendor is None:
            continue

        orders = db.scalars(
            select(PurchaseOrder).where(
                PurchaseOrder.supplier_id == supplier.id,
                PurchaseOrder.vendor_id == vendor.id,
            )
        ).all()
        delivered = [o for o in orders if o.status == "delivered"]

        rows.append(
            BookRow(
                vendor=vendor,
                connection=connection,
                order_count=len(orders),
                delivered_count=len(delivered),
                revenue=round(sum(o.amount_total for o in delivered), 2),
                outstanding=_outstanding_pair(db, vendor.id, supplier.id),
                fill=fill_rate(db, supplier.id, vendor_id=vendor.id),
                last_order_at=max(
                    (o.placed_at for o in orders if o.placed_at), default=None
                ),
            )
        )

    rows.sort(key=lambda r: r.revenue, reverse=True)
    return rows


def _outstanding_pair(
    db: Session, vendor_id: uuid.UUID, supplier_id: uuid.UUID
) -> float:
    balance = 0.0
    for entry in db.scalars(
        select(LedgerEntry).where(
            LedgerEntry.vendor_id == vendor_id,
            LedgerEntry.supplier_id == supplier_id,
        )
    ):
        balance += -entry.amount if entry.kind == "payment" else entry.amount
    return round(balance, 2)


# --------------------------------------------------------------- dead lines
def dead_lines(
    db: Session, supplier: Supplier, *, days: int = DEAD_LINE_DAYS
) -> list[DeadLine]:
    """Catalogue lines nobody has ordered lately.

    Worth surfacing because a wholesaler's shelf space and working capital are
    as finite as a shopkeeper's, and a line that has not moved in a month is
    money sitting still.
    """
    cutoff = utcnow() - timedelta(days=days)
    entries = db.scalars(
        select(CatalogEntry).where(
            CatalogEntry.supplier_id == supplier.id,
            CatalogEntry.active.is_(True),
        )
    ).all()

    rows: list[DeadLine] = []
    for entry in entries:
        last = db.scalar(
            select(func.max(PurchaseOrder.placed_at))
            .join(
                PurchaseOrderLine,
                PurchaseOrderLine.order_id == PurchaseOrder.id,
            )
            .where(
                PurchaseOrder.supplier_id == supplier.id,
                PurchaseOrderLine.catalog_entry_id == entry.id,
            )
        )
        if last is not None and last >= cutoff:
            continue
        rows.append(
            DeadLine(
                entry=entry,
                days_since_last_order=(utcnow() - last).days if last else None,
            )
        )
    return rows
