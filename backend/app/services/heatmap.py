"""Hyperlocal demand heatmap (Report 10.2, zero-logistics B2B mediator track).

Aggregates demand across vendors into geographic cells so a distributor can see
where a category is moving, and a vendor can see whether their own shortage is
local or general.

Privacy is the constraint that shapes this. A per-store heatmap would expose
individual vendors' sales to competitors and distributors, so demand is only
ever emitted for a cell once at least `MIN_VENDORS_PER_CELL` stores contribute
to it. Cells below that threshold are dropped, not merged upward -- merging
would let a caller difference two zoom levels and recover the suppressed store.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import InventoryItem, Supplier, Transaction, Vendor

# k-anonymity threshold. Below this a cell describes one identifiable store.
MIN_VENDORS_PER_CELL = 3

# Grid resolution in degrees. ~0.01 deg is roughly 1.1 km at Pune's latitude --
# fine enough to be useful to a distributor, coarse enough to hold several
# stores per cell.
DEFAULT_CELL_SIZE = 0.01


@dataclass
class HeatCell:
    lat: float
    lon: float
    intensity: float      # 0-1, normalised across the returned set
    demand_qty: float
    demand_value: float
    vendor_count: int
    top_sku: str | None
    shortage_count: int


@dataclass
class HeatmapResult:
    cells: list[HeatCell]
    suppressed_cells: int
    category: str | None
    days: int
    max_demand: float
    total_demand: float
    suppliers: list[dict]


def _snap(value: float, size: float) -> float:
    """Snap a coordinate to its cell centre."""
    return round((value // size) * size + size / 2, 6)


def build_heatmap(
    db: Session,
    *,
    category: str | None = None,
    sku_name: str | None = None,
    days: int = 30,
    city: str = "Pune",
    cell_size: float = DEFAULT_CELL_SIZE,
    include_suppliers: bool = True,
) -> HeatmapResult:
    """Aggregate recent sales into geographic demand cells."""
    since = date.today() - timedelta(days=days)

    stmt = (
        select(Transaction, InventoryItem, Vendor)
        .join(InventoryItem, InventoryItem.id == Transaction.item_id)
        .join(Vendor, Vendor.id == Transaction.vendor_id)
        .where(
            Transaction.type == "sale",
            Vendor.lat.is_not(None),
            Vendor.lon.is_not(None),
            Vendor.city == city,
        )
    )
    if category:
        stmt = stmt.where(InventoryItem.category == category)
    if sku_name:
        stmt = stmt.where(InventoryItem.sku_name == sku_name)

    buckets: dict[tuple[float, float], dict] = defaultdict(
        lambda: {
            "qty": 0.0,
            "value": 0.0,
            "vendors": set(),
            "skus": defaultdict(float),
        }
    )

    for txn, item, vendor in db.execute(stmt).all():
        if txn.occurred_at.date() < since:
            continue
        key = (_snap(vendor.lat, cell_size), _snap(vendor.lon, cell_size))
        bucket = buckets[key]
        bucket["qty"] += txn.qty
        bucket["value"] += txn.qty * (txn.unit_value or item.unit_price or 0)
        bucket["vendors"].add(vendor.id)
        bucket["skus"][item.sku_name] += txn.qty

    # Vendors currently below their reorder point, by cell, so the map can show
    # where restocking pressure is building rather than only where sales
    # already happened.
    shortage_stmt = (
        select(InventoryItem, Vendor)
        .join(Vendor, Vendor.id == InventoryItem.vendor_id)
        .where(
            InventoryItem.current_qty <= InventoryItem.reorder_point,
            Vendor.lat.is_not(None),
            Vendor.city == city,
        )
    )
    if category:
        shortage_stmt = shortage_stmt.where(InventoryItem.category == category)
    if sku_name:
        shortage_stmt = shortage_stmt.where(InventoryItem.sku_name == sku_name)

    shortages: dict[tuple[float, float], int] = defaultdict(int)
    for _, vendor in db.execute(shortage_stmt).all():
        shortages[(_snap(vendor.lat, cell_size), _snap(vendor.lon, cell_size))] += 1

    eligible = {
        key: data
        for key, data in buckets.items()
        if len(data["vendors"]) >= MIN_VENDORS_PER_CELL
    }
    suppressed = len(buckets) - len(eligible)

    max_demand = max((d["qty"] for d in eligible.values()), default=0.0)

    cells = [
        HeatCell(
            lat=lat,
            lon=lon,
            # Normalised against the busiest cell in this response, so the map
            # is readable whether the filter returns dairy citywide or one SKU
            # in one neighbourhood.
            intensity=round(data["qty"] / max_demand, 3) if max_demand else 0.0,
            demand_qty=round(data["qty"], 2),
            demand_value=round(data["value"], 2),
            vendor_count=len(data["vendors"]),
            top_sku=max(data["skus"], key=data["skus"].get) if data["skus"] else None,
            shortage_count=shortages.get((lat, lon), 0),
        )
        for (lat, lon), data in eligible.items()
    ]
    cells.sort(key=lambda c: c.intensity, reverse=True)

    supplier_rows: list[dict] = []
    if include_suppliers:
        sup_stmt = select(Supplier).where(Supplier.city == city)
        for sup in db.scalars(sup_stmt).all():
            cats = sup.categories or []
            if category and cats and category not in cats:
                continue
            supplier_rows.append(
                {
                    "id": str(sup.id),
                    "name": sup.name,
                    "kind": sup.kind,
                    "lat": sup.lat,
                    "lon": sup.lon,
                    "locality": sup.locality,
                    "categories": cats,
                    "lead_days": sup.lead_days,
                    "rating": sup.rating,
                    "min_order_value": sup.min_order_value,
                }
            )

    return HeatmapResult(
        cells=cells,
        suppressed_cells=suppressed,
        category=category,
        days=days,
        max_demand=round(max_demand, 2),
        total_demand=round(sum(c.demand_qty for c in cells), 2),
        suppliers=supplier_rows,
    )
