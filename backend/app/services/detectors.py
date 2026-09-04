"""Noticing things as they happen.

Three detectors, each a pure function from state to zero or more events. Pure
because a detector that needs a socket, a clock and a running server to test is
a detector nobody changes with confidence.

They share a discipline: say *why*, not just *what*. "Milk is selling three
times normal" is a fact a shopkeeper can act on; "anomaly detected" is a
notification they will learn to dismiss.
"""
from __future__ import annotations

import math
import statistics
import uuid
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.db import utcnow
from ..models import InventoryItem, Transaction, Vendor
from .pooling import MIN_VENDORS_FOR_POOL

# How much of a trading day must have elapsed before today's total means
# anything. Below this, one early customer looks like a surge. 0.3 of a
# 07:00-21:00 day is about 11am.
MIN_DAY_FRACTION = 0.3

# Standard deviations from the same-weekday mean before it is worth saying.
# Two is the conventional line and, on eight-odd samples, already generous.
ANOMALY_Z = 2.0

# Weeks of history to build the baseline from. Eight gives eight samples per
# weekday -- thin, which is why the detector reports its own confidence.
BASELINE_WEEKS = 8

# Floor on the baseline's spread, as a fraction of its mean.
#
# Guards two failures at once. A perfectly steady history gives a standard
# deviation of zero, which makes the z-score undefined and would silence the
# detector in precisely the case where a jump is most obviously a jump. And a
# tiny-but-nonzero spread produces an enormous z off nearly identical samples,
# which would flag ordinary noise as a crisis.
#
# Real kirana demand swings far wider than fifteen percent day to day, so this
# only ever binds on degenerate data -- which is exactly when it should.
MIN_RELATIVE_SPREAD = 0.15

# A neighbourhood shop's trading day, used to work out how much of it is gone.
DAY_OPENS = 7
DAY_CLOSES = 21

# Shops going short of the same SKU inside this window are one event, not
# several coincidences.
SURGE_WINDOW_HOURS = 6


@dataclass(frozen=True)
class Detection:
    """What a detector found. Turned into an event and an alert by the caller."""

    kind: str  # anomaly | stockout | surge
    severity: str  # info | warning | urgent
    title: str
    body: str
    payload: dict


def approx(amount: float) -> str:
    """A quantity at the precision it deserves.

    "Down to 63.19 pc" reads as machine output. The same magnitude rule the
    client applies: whole numbers above ten, one decimal below, where the
    fraction is still real stock rather than noise.
    """
    if amount >= 10:
        return f"{round(amount):g}"
    return f"{round(amount * 10) / 10:g}"


def day_fraction(now: datetime | None = None) -> float:
    """How much of the trading day has passed, 0..1."""
    now = now or utcnow()
    elapsed = now.hour + now.minute / 60 - DAY_OPENS
    return max(0.0, min(1.0, elapsed / (DAY_CLOSES - DAY_OPENS)))


def _sold_between(
    db: Session, item_id: uuid.UUID, start: datetime, end: datetime
) -> float:
    total = db.scalar(
        select(func.coalesce(func.sum(Transaction.qty), 0.0)).where(
            Transaction.item_id == item_id,
            Transaction.type == "sale",
            Transaction.occurred_at >= start,
            Transaction.occurred_at < end,
        )
    )
    return float(total or 0.0)


def _same_weekday_totals(
    db: Session, item_id: uuid.UUID, *, today: date, weeks: int = BASELINE_WEEKS
) -> list[float]:
    """Daily totals for the same weekday over recent weeks.

    Same-weekday rather than a flat trailing mean because a neighbourhood
    shop's Saturday looks nothing like its Tuesday -- the seed models a 35%
    weekend lift precisely because that is what the real pattern is. Comparing
    a Saturday against a mixed baseline would flag every Saturday as a surge.
    """
    totals: list[float] = []
    for week in range(1, weeks + 1):
        day = today - timedelta(days=7 * week)
        start = datetime.combine(day, time.min, timezone.utc)
        totals.append(_sold_between(db, item_id, start, start + timedelta(days=1)))
    return totals


# ------------------------------------------------------------------ anomaly
def detect_anomaly(
    db: Session,
    item: InventoryItem,
    *,
    now: datetime | None = None,
) -> Detection | None:
    """Is today's demand for this item unlike its recent same-weekday self?

    Deliberately does not use the forecast cache. That cache holds no value for
    today by design -- today's sales are a partial observation, not a
    prediction, which is the whole reason its window opens tomorrow. The
    baseline that does exist is the trailing same-weekday distribution.
    """
    now = now or utcnow()
    elapsed = day_fraction(now)
    if elapsed < MIN_DAY_FRACTION:
        return None

    today = now.date()
    start = datetime.combine(today, time.min, timezone.utc)
    actual = _sold_between(db, item.id, start, now)

    history = _same_weekday_totals(db, item.id, today=today)
    observed = [t for t in history if t > 0]
    if len(observed) < 3:
        # Three samples is the floor at which a standard deviation means
        # anything at all. Below it the honest output is silence.
        return None

    mean = statistics.fmean(observed)
    if mean <= 0:
        return None

    spread = max(statistics.pstdev(observed), mean * MIN_RELATIVE_SPREAD)

    # Compare like with like: the baseline is a whole day, the actual is a
    # partial one, so the baseline is scaled to the same point in the day.
    expected = mean * elapsed
    z = (actual - expected) / (spread * math.sqrt(elapsed))

    if abs(z) < ANOMALY_Z:
        return None

    ratio = actual / expected if expected > 0 else 0.0
    surging = z > 0
    confidence = "high" if len(observed) >= 6 else "low"

    if surging:
        rate = actual / max(elapsed, 0.01)
        cover_days = item.current_qty / rate if rate > 0 else None
        hours = None if cover_days is None else cover_days * (DAY_CLOSES - DAY_OPENS)

        body = (
            f"{ratio:.1f}× a normal {today.strftime('%A')} so far."
            if hours is None or hours > 48
            else f"{ratio:.1f}× a normal {today.strftime('%A')} so far — "
            f"about {hours:.0f} hours of stock left at this rate."
        )
        return Detection(
            kind="anomaly",
            severity="urgent" if (hours or 99) < 12 else "warning",
            title=f"{item.sku_name} is selling fast",
            body=body,
            payload={
                "item_id": str(item.id),
                "sku_name": item.sku_name,
                "direction": "up",
                "ratio": round(ratio, 2),
                "z": round(z, 2),
                "confidence": confidence,
            },
        )

    return Detection(
        kind="anomaly",
        severity="info",
        title=f"{item.sku_name} is slow today",
        body=f"{ratio:.0%} of a normal {today.strftime('%A')} so far. "
        "Worth checking it is on the shelf and priced right.",
        payload={
            "item_id": str(item.id),
            "sku_name": item.sku_name,
            "direction": "down",
            "ratio": round(ratio, 2),
            "z": round(z, 2),
            "confidence": confidence,
        },
    )


# ----------------------------------------------------------------- stockout
def detect_stockout(
    item: InventoryItem, *, previous_qty: float
) -> Detection | None:
    """Fires on the crossing into short, once.

    Edge-triggered, which is the whole design. Level-triggered -- "is it below
    the line?" -- re-fires on every subsequent sale, and an alert that arrives
    six times for one event is an alert people learn to swipe away.

    `previous_qty` is a parameter rather than something read back, so a caller
    cannot accidentally compare a value against itself after mutating it.
    """
    threshold = item.reorder_point
    if threshold <= 0:
        return None

    was_fine = previous_qty > threshold
    is_short = item.current_qty <= threshold
    if not (was_fine and is_short):
        return None

    empty = item.current_qty <= 0.001
    return Detection(
        kind="stockout",
        severity="urgent" if empty else "warning",
        title=f"{item.sku_name} {'is finished' if empty else 'is running low'}",
        body=f"Down to {approx(item.current_qty)} {item.unit}, "
        f"below your reorder point of {approx(threshold)}.",
        payload={
            "item_id": str(item.id),
            "sku_name": item.sku_name,
            "category": item.category,
            "current_qty": item.current_qty,
            "reorder_point": threshold,
            "empty": empty,
        },
    )


# -------------------------------------------------------------------- surge
@dataclass
class SurgeFinding:
    detection: Detection
    vendor_ids: set[uuid.UUID]
    sku_name: str
    category: str
    locality: str


def detect_surge(
    db: Session,
    *,
    sku_name: str,
    locality: str,
    now: datetime | None = None,
    window_hours: int = SURGE_WINDOW_HOURS,
) -> SurgeFinding | None:
    """Several shops in one locality going short of the same thing at once.

    That is not three coincidences, it is a group order forming. `pooling.py`
    already computes candidates on a manual sweep and already sets the
    threshold at three; this makes the same rule event-driven, so a pool opens
    while the shortage is live rather than whenever someone next runs the
    sweep.
    """
    now = now or utcnow()
    since = now - timedelta(hours=window_hours)

    rows = db.execute(
        select(InventoryItem, Vendor)
        .join(Vendor, Vendor.id == InventoryItem.vendor_id)
        .where(
            func.lower(InventoryItem.sku_name) == sku_name.lower(),
            Vendor.locality == locality,
            InventoryItem.current_qty <= InventoryItem.reorder_point,
            InventoryItem.reorder_point > 0,
            InventoryItem.last_updated >= since,
        )
    ).all()

    if len(rows) < MIN_VENDORS_FOR_POOL:
        return None

    vendor_ids = {vendor.id for _, vendor in rows}
    if len(vendor_ids) < MIN_VENDORS_FOR_POOL:
        return None

    shortfall = sum(
        max(0.0, item.reorder_point - item.current_qty) for item, _ in rows
    )
    first_item = rows[0][0]

    return SurgeFinding(
        detection=Detection(
            kind="surge",
            severity="info",
            title=f"{len(vendor_ids)} shops in {locality} need {sku_name}",
            body=f"About {approx(shortfall)} {first_item.unit} short between them. "
            "Ordering together clears a bulk price none of you reach alone.",
            payload={
                "sku_name": sku_name,
                "locality": locality,
                "shop_count": len(vendor_ids),
                "shortfall": round(shortfall, 2),
                "unit": first_item.unit,
                "category": first_item.category,
            },
        ),
        vendor_ids=vendor_ids,
        sku_name=sku_name,
        category=first_item.category,
        locality=locality,
    )
