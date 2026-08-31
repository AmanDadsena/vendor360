"""Ranking who to buy from.

A vendor staring at a low-stock row has one question — *who do I order this
from?* — and four answers that pull in different directions: price, speed,
reliability, and distance. This module resolves them into an ordering, and
attaches the reasoning so the vendor can disagree with it.

The reasoning matters as much as the ranking. A list sorted by an invisible
score is a list a shopkeeper stops trusting the first time it disagrees with
what they already know about a supplier.
"""
from __future__ import annotations

import math
import uuid
from dataclasses import dataclass, field

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import (
    CatalogEntry,
    InventoryItem,
    Supplier,
    Transaction,
    Vendor,
    VendorDistributor,
)
from .ordering import PackPlan, fill_rate, plan_packs

# How much each factor moves the score. Cost dominates because it is what a
# vendor optimises on their own; the others exist to stop cost winning when it
# should not — a case that arrives after the shelf empties is not cheap.
W_COST = 0.55
W_RELIABILITY = 0.20
W_SPEED = 0.15
W_DISTANCE = 0.10

# A supplier who cannot arrive before the stockout loses most of its score
# however cheap it is. Not zero: sometimes nobody can arrive in time and the
# vendor still has to pick one.
LATE_PENALTY = 0.45

# Applied when a supplier has no completed orders yet, so an unknown quantity
# ranks below a proven one at equal price without being excluded.
UNPROVEN_RELIABILITY = 0.75

# Beyond this much stock in hand, lead time stops being a real consideration
# and the speed weight is handed back to price. A shop with a month of cover
# should take the cheaper wholesaler and wait.
URGENCY_HORIZON_DAYS = 10.0

# What a unit of forced surplus is still worth, by shelf life. A sack of rice
# bought early is nearly all recovered; four days of extra milk is not.
SALVAGE_BY_SHELF_LIFE: tuple[tuple[int | None, float], ...] = (
    (7, 0.15),
    (30, 0.35),
    (90, 0.60),
    (None, 0.85),
)


@dataclass
class SourcingOption:
    supplier: Supplier
    entry: CatalogEntry
    plan: PackPlan
    lead_days: int
    arrives_in_time: bool
    fill: float | None
    distance_km: float | None
    score: float = 0.0
    reasons: list[str] = field(default_factory=list)

    @property
    def unit_landed(self) -> float:
        """What this option really costs, per unit the shop actually needed.

        Charging the whole outlay against the requested quantity — rather than
        against everything the pack forced them to take — is what stops a
        cheap-per-unit listing with a five-case minimum from winning a
        two-case need. Surplus is credited back at whatever it can still be
        sold for, which for dairy is very little and for rice is most of it.
        """
        if self.plan.qty_requested <= 0:
            return 0.0

        salvage = salvage_rate(self.entry.category)
        recovered = self.plan.surplus * self.entry.unit_price * salvage
        return max(0.0, self.plan.cost - recovered) / self.plan.qty_requested


def salvage_rate(category: str) -> float:
    """How much of an over-ordered unit's value survives until it can be sold.

    Read off the category shelf life the catalogue already declares, so the
    ranking inherits the same perishability knowledge that drives safety stock
    and the expiry board rather than inventing a second opinion.
    """
    from .catalog import category as category_spec

    shelf_life = category_spec(category).shelf_life_days
    for threshold, rate in SALVAGE_BY_SHELF_LIFE:
        if threshold is None or shelf_life is not None and shelf_life < threshold:
            return rate
    return SALVAGE_BY_SHELF_LIFE[-1][1]


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance. Good enough at city scale, and dependency-free."""
    radius = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
        * math.sin(d_lon / 2) ** 2
    )
    return radius * 2 * math.asin(math.sqrt(a))


def daily_rate(db: Session, item_id: uuid.UUID, days: int = 21) -> float:
    """Mean units sold per day over the recent window.

    Used only to convert stock into days of cover, so a rough recent mean is
    the right instrument — the forecaster's richer view is not needed to answer
    "will this last until Thursday".
    """
    from ..core.db import utcnow
    from datetime import timedelta

    since = utcnow() - timedelta(days=days)
    total = db.scalar(
        select(func.sum(Transaction.qty)).where(
            Transaction.item_id == item_id,
            Transaction.type == "sale",
            Transaction.occurred_at >= since,
        )
    )
    return round((total or 0) / days, 3)


def days_of_cover(current_qty: float, rate: float) -> float | None:
    """How long the shelf lasts. None when nothing is selling."""
    if rate <= 0:
        return None
    return round(current_qty / rate, 2)


def rank_options(
    db: Session,
    *,
    vendor: Vendor,
    item: InventoryItem,
    shortfall: float,
    cover_days: float | None,
) -> list[SourcingOption]:
    """Score every connected distributor who lists this SKU.

    Only connected suppliers are considered. Surfacing a price from a
    wholesaler the vendor has no relationship with would be a quote they cannot
    act on, and the discovery screen already exists for finding new ones.
    """
    supplier_ids = db.scalars(
        select(VendorDistributor.supplier_id).where(
            VendorDistributor.vendor_id == vendor.id,
            VendorDistributor.status == "active",
        )
    ).all()
    if not supplier_ids:
        return []

    rows = db.execute(
        select(CatalogEntry, Supplier)
        .join(Supplier, Supplier.id == CatalogEntry.supplier_id)
        .where(
            CatalogEntry.supplier_id.in_(supplier_ids),
            CatalogEntry.active.is_(True),
            func.lower(CatalogEntry.sku_name) == item.sku_name.lower(),
        )
    ).all()

    options: list[SourcingOption] = []
    for entry, supplier in rows:
        if entry.available_packs is not None and entry.available_packs <= 0:
            continue

        plan = plan_packs(shortfall, entry.pack_size, entry.pack_price, entry.moq_packs)
        if plan.packs <= 0:
            continue

        lead = entry.lead_days if entry.lead_days is not None else supplier.lead_days
        options.append(
            SourcingOption(
                supplier=supplier,
                entry=entry,
                plan=plan,
                lead_days=lead,
                arrives_in_time=cover_days is None or lead <= cover_days,
                fill=fill_rate(db, supplier.id, vendor_id=None),
                distance_km=_distance(vendor, supplier),
            )
        )

    if not options:
        return []

    _score(options, cover_days)
    options.sort(key=lambda o: o.score, reverse=True)
    _explain(options, cover_days)
    return options


def _distance(vendor: Vendor, supplier: Supplier) -> float | None:
    if vendor.lat is None or vendor.lon is None:
        return None
    return round(haversine_km(vendor.lat, vendor.lon, supplier.lat, supplier.lon), 2)


def urgency(cover_days: float | None) -> float:
    """How much lead time should matter right now, from 0 to 1.

    A shop with two days of stock is buying speed. A shop with a month of it is
    buying price, and ranking a pricier wholesaler first because it happens to
    be faster would be advice a shopkeeper is right to ignore.
    """
    if cover_days is None:
        # Nothing is selling, so nothing is running out. Price it is.
        return 0.0
    return max(0.0, min(1.0, 1.0 - cover_days / URGENCY_HORIZON_DAYS))


def _score(options: list[SourcingOption], cover_days: float | None) -> None:
    """Normalise each factor against the field, then combine.

    Scoring relative to the best available option rather than against absolute
    thresholds keeps the ranking meaningful whether a vendor has two suppliers
    or twenty, and whether the SKU costs ₹8 or ₹800.

    The speed weight is scaled by urgency, and whatever it gives up is handed
    to price — so the same two suppliers can legitimately swap places depending
    on how much stock is left on the shelf.
    """
    best_unit = min(o.unit_landed for o in options) or 1.0
    best_lead = min(o.lead_days for o in options)
    worst_lead = max(o.lead_days for o in options)
    lead_spread = max(1, worst_lead - best_lead)

    distances = [o.distance_km for o in options if o.distance_km is not None]
    worst_distance = max(distances) if distances else 0

    w_speed = W_SPEED * urgency(cover_days)
    w_cost = W_COST + (W_SPEED - w_speed)

    for option in options:
        # 1.0 for the cheapest per needed unit, falling away from there.
        cost_score = best_unit / option.unit_landed if option.unit_landed else 0.0

        reliability = option.fill if option.fill is not None else UNPROVEN_RELIABILITY
        speed = 1.0 - (option.lead_days - best_lead) / lead_spread

        if option.distance_km is None or worst_distance <= 0:
            proximity = 0.5
        else:
            proximity = 1.0 - (option.distance_km / worst_distance)

        score = (
            w_cost * cost_score
            + W_RELIABILITY * reliability
            + w_speed * speed
            + W_DISTANCE * proximity
        )
        if not option.arrives_in_time:
            score *= 1 - LATE_PENALTY

        option.score = round(score, 4)


def _explain(options: list[SourcingOption], cover_days: float | None) -> None:
    """Attach the two or three facts that actually decided the ordering.

    Written against the runner-up rather than in absolutes, because "₹1.20
    cheaper per kg" is a reason and "₹23.00 per kg" is just a number.
    """
    leader = options[0]
    runner_up = options[1] if len(options) > 1 else None

    for option in options:
        reasons: list[str] = []

        if runner_up is not None and option is leader:
            saving = runner_up.unit_landed - leader.unit_landed
            if saving > 0.01:
                reasons.append(
                    f"₹{saving:.2f} cheaper per {leader.entry.unit}"
                )
            faster = runner_up.lead_days - leader.lead_days
            if faster > 0:
                reasons.append(
                    f"arrives {faster} day{'s' if faster > 1 else ''} sooner"
                )

        if option.fill is not None and option.fill >= 0.9:
            reasons.append(f"fills {option.fill * 100:.0f}% of orders")
        elif option.fill is not None and option.fill < 0.75:
            reasons.append(f"only fills {option.fill * 100:.0f}% of orders")
        elif option.fill is None:
            reasons.append("no order history yet")

        if not option.arrives_in_time and cover_days is not None:
            reasons.append(
                f"arrives in {option.lead_days}d, stock lasts {cover_days:.0f}d"
            )
        elif option.arrives_in_time and option.lead_days == 0:
            reasons.append("same-day delivery")

        if option.plan.moq_applied:
            reasons.append(
                f"minimum {option.entry.moq_packs} "
                f"pack{'s' if option.entry.moq_packs > 1 else ''}"
            )
        elif option.plan.surplus > 0:
            reasons.append(
                f"{option.plan.surplus:g} {option.entry.unit} extra "
                f"(sold by the {option.plan.pack_size:g})"
            )

        if option.distance_km is not None and option.distance_km <= 2:
            reasons.append(f"{option.distance_km:g} km away")

        option.reasons = reasons[:3]
