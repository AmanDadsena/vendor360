"""Multi-vendor collective bargaining (PRD 5.1, TC-B01/B02).

Small vendors individually order below every wholesale discount threshold.
Pooling the same shortage across a locality reaches the threshold that none of
them reaches alone -- the discount large supermarkets get by default.

The engine only proposes a pool when enough vendors are genuinely short of the
same SKU. Proposing one for a single vendor would be a coupon with extra steps,
and would teach vendors to ignore the feature.
"""
from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.db import utcnow
from ..models import BargainPool, InventoryItem, PoolMember, Vendor

# Fewer participants than this is not a pool worth coordinating.
MIN_VENDORS_FOR_POOL = 3

# Bulk discount tiers: (multiple of the individual order, discount fraction).
# Modelled on how Indian FMCG distributors actually price -- step changes at
# case and multi-case volumes, not a smooth curve.
DISCOUNT_TIERS: list[tuple[float, float]] = [
    (3.0, 0.04),
    (6.0, 0.07),
    (12.0, 0.11),
    (25.0, 0.15),
]

POOL_WINDOW_HOURS = 48


@dataclass
class PoolCandidate:
    sku_name: str
    category: str
    unit: str
    locality: str
    vendor_ids: list[uuid.UUID]
    total_shortfall: float
    base_unit_price: float
    bulk_unit_price: float
    discount_pct: float
    est_saving: float


def discount_for(total_qty: float, typical_single_order: float) -> float:
    """Discount fraction earned by a combined order."""
    if typical_single_order <= 0:
        return 0.0
    multiple = total_qty / typical_single_order
    earned = 0.0
    for threshold, discount in DISCOUNT_TIERS:
        if multiple >= threshold:
            earned = discount
    return earned


def find_pool_candidates(
    db: Session, *, locality: str | None = None
) -> list[PoolCandidate]:
    """Group vendors short of the same SKU in the same locality.

    Shortfall is measured against each vendor's own dynamic reorder point, so a
    pool forms around vendors who actually need stock now -- not around whoever
    happens to hold the least.
    """
    stmt = (
        select(InventoryItem, Vendor)
        .join(Vendor, Vendor.id == InventoryItem.vendor_id)
        .where(InventoryItem.current_qty <= InventoryItem.reorder_point)
    )
    if locality:
        stmt = stmt.where(Vendor.locality == locality)

    grouped: dict[tuple[str, str], list[tuple[InventoryItem, Vendor]]] = defaultdict(list)
    for item, vendor in db.execute(stmt).all():
        grouped[(item.sku_name, vendor.locality or "Unknown")].append((item, vendor))

    candidates: list[PoolCandidate] = []

    for (sku, area), rows in grouped.items():
        if len(rows) < MIN_VENDORS_FOR_POOL:
            continue

        shortfalls = []
        for item, _ in rows:
            # Order up to twice the reorder point: the buffer plus a lead
            # time's cover, matching what safety_stock recommends.
            target = max(item.reorder_point * 2, item.reorder_point + 1)
            shortfalls.append(max(0.0, target - item.current_qty))

        total = sum(shortfalls)
        if total <= 0:
            continue

        typical = total / len(rows)
        base_price = max(
            (item.unit_cost for item, _ in rows if item.unit_cost > 0), default=0.0
        )
        if base_price <= 0:
            continue

        discount = discount_for(total, typical)
        if discount <= 0:
            continue

        bulk_price = round(base_price * (1 - discount), 2)
        candidates.append(
            PoolCandidate(
                sku_name=sku,
                category=rows[0][0].category,
                unit=rows[0][0].unit,
                locality=area,
                vendor_ids=[v.id for _, v in rows],
                total_shortfall=round(total, 2),
                base_unit_price=round(base_price, 2),
                bulk_unit_price=bulk_price,
                discount_pct=round(discount * 100, 1),
                est_saving=round((base_price - bulk_price) * total, 2),
            )
        )

    return sorted(candidates, key=lambda c: c.est_saving, reverse=True)


def materialise_pools(db: Session, candidates: list[PoolCandidate]) -> list[BargainPool]:
    """Persist candidates as open pools, skipping SKUs already pooled here."""
    created: list[BargainPool] = []

    for cand in candidates:
        existing = db.scalar(
            select(BargainPool).where(
                BargainPool.sku_name == cand.sku_name,
                BargainPool.locality == cand.locality,
                BargainPool.status == "open",
            )
        )
        if existing is not None:
            continue

        pool = BargainPool(
            sku_name=cand.sku_name,
            category=cand.category,
            unit=cand.unit,
            locality=cand.locality,
            target_qty=cand.total_shortfall,
            committed_qty=0,
            base_unit_price=cand.base_unit_price,
            bulk_unit_price=cand.bulk_unit_price,
            status="open",
            closes_at=utcnow() + timedelta(hours=POOL_WINDOW_HOURS),
        )
        db.add(pool)
        created.append(pool)

    db.commit()
    return created


def join_pool(
    db: Session, *, pool_id: uuid.UUID, vendor_id: uuid.UUID, qty: float
) -> BargainPool:
    member = db.scalar(
        select(PoolMember).where(
            PoolMember.pool_id == pool_id, PoolMember.vendor_id == vendor_id
        )
    )
    if member is None:
        member = PoolMember(pool_id=pool_id, vendor_id=vendor_id, qty=qty)
        db.add(member)
    else:
        member.qty = qty
        member.opted_out = False

    db.flush()
    return _recompute(db, pool_id)


def leave_pool(db: Session, *, pool_id: uuid.UUID, vendor_id: uuid.UUID) -> BargainPool:
    """TC-B02 — opting out adjusts the pool total, it does not delete history."""
    member = db.scalar(
        select(PoolMember).where(
            PoolMember.pool_id == pool_id, PoolMember.vendor_id == vendor_id
        )
    )
    if member is not None:
        member.opted_out = True
        db.flush()
    return _recompute(db, pool_id)


def _recompute(db: Session, pool_id: uuid.UUID) -> BargainPool:
    """Recompute committed quantity and the discount it currently earns.

    The price is re-derived on every join and leave rather than fixed at
    creation: a pool that loses a member must lose the discount that member's
    volume bought, or vendors would be quoted a price the supplier will not
    honour.
    """
    pool = db.get(BargainPool, pool_id)
    members = [m for m in pool.members if not m.opted_out]

    pool.committed_qty = round(sum(m.qty for m in members), 2)

    if members:
        typical = pool.committed_qty / len(members)
        discount = discount_for(pool.committed_qty, typical)
        pool.bulk_unit_price = round(pool.base_unit_price * (1 - discount), 2)
    else:
        pool.bulk_unit_price = pool.base_unit_price

    db.commit()
    return pool
