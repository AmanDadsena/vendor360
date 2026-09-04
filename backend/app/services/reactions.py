"""What happens the moment stock moves.

Every path that changes a quantity -- the online movement endpoint, the offline
sync replay, voice capture, an order delivery -- funnels through here, so the
detectors run once, in one place, with one definition of what counts as a
change worth reacting to.

Deliberately failure-tolerant. A detector raising must never turn a recorded
sale into a 500: the sale is the thing that matters, and noticing something
about it is a bonus. So the whole reaction is wrapped, and a failure is logged
rather than propagated.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.db import utcnow
from ..models import Alert, BargainPool, InventoryItem, Vendor
from .audiences import anonymous, for_locality_surge
from .detectors import detect_anomaly, detect_stockout, detect_surge
from .event_bus import DomainEvent, bus
from .notifier import notify, notify_many
from .pooling import find_pool_candidates, materialise_pools

log = logging.getLogger(__name__)

# The same detection about the same item should not arrive twice in an hour.
# Without this, a shop selling steadily past its reorder point re-alerts on
# every wobble across the line as restocks and sales interleave.
QUIET_HOURS = 1


def _recently_alerted(
    db: Session, *, vendor_id: uuid.UUID, kind: str, subject_id: uuid.UUID
) -> bool:
    cutoff = utcnow() - timedelta(hours=QUIET_HOURS)
    return (
        db.scalar(
            select(Alert.id).where(
                Alert.vendor_id == vendor_id,
                Alert.kind == kind,
                Alert.subject_id == subject_id,
                Alert.created_at >= cutoff,
            )
        )
        is not None
    )


def on_stock_changed(
    db: Session,
    *,
    vendor: Vendor,
    item: InventoryItem,
    previous_qty: float,
    was_sale: bool,
    now: datetime | None = None,
) -> None:
    """Run the detectors against one item that just moved.

    Called after the quantity is written and before the request returns, so a
    shop and its consenting distributors learn about a crossing in the same
    round trip that caused it.
    """
    try:
        _react(
            db,
            vendor=vendor,
            item=item,
            previous_qty=previous_qty,
            was_sale=was_sale,
            now=now,
        )
    except Exception:  # noqa: BLE001 - a detector must never fail a sale
        log.exception(
            "detectors failed for item %s; the movement itself is unaffected",
            item.id,
        )


def _react(
    db: Session,
    *,
    vendor: Vendor,
    item: InventoryItem,
    previous_qty: float,
    was_sale: bool,
    now: datetime | None,
) -> None:
    # ------------------------------------------------------------ stockout
    stockout = detect_stockout(item, previous_qty=previous_qty)
    if stockout and not _recently_alerted(
        db, vendor_id=vendor.id, kind="stockout", subject_id=item.id
    ):
        notify(db, stockout, vendor=vendor, category=item.category, subject_id=item.id)

        # A crossing is also the moment to ask whether the locality is short.
        if vendor.locality:
            _react_to_surge(db, vendor=vendor, item=item, now=now)

    # ------------------------------------------------------------- anomaly
    # Sales only. A restock changing the day's total says nothing about demand.
    if was_sale and not _recently_alerted(
        db, vendor_id=vendor.id, kind="anomaly", subject_id=item.id
    ):
        anomaly = detect_anomaly(db, item, now=now)
        if anomaly:
            notify(
                db, anomaly, vendor=vendor, category=item.category, subject_id=item.id
            )

    # ------------------------------------------------------------- heatmap
    # A sale shifts the demand picture. The payload carries no shop identity --
    # the client re-reads the heatmap endpoint, which applies k-anonymity.
    if was_sale and vendor.locality:
        bus.publish(
            DomainEvent(
                kind="heatmap",
                audience=anonymous(),
                payload={
                    "locality": vendor.locality,
                    "category": item.category,
                    "lat": vendor.lat,
                    "lon": vendor.lon,
                },
            )
        )


def _react_to_surge(
    db: Session,
    *,
    vendor: Vendor,
    item: InventoryItem,
    now: datetime | None,
) -> None:
    """Open a pool when a locality goes short of the same thing together."""
    finding = detect_surge(
        db, sku_name=item.sku_name, locality=vendor.locality, now=now
    )
    if finding is None:
        return

    # Do not re-open one that is already running.
    existing = db.scalar(
        select(BargainPool).where(
            BargainPool.sku_name == item.sku_name,
            BargainPool.locality == vendor.locality,
            BargainPool.status == "open",
        )
    )
    pool = existing
    if pool is None:
        # Reuse the pooling engine rather than hand-rolling a second pool
        # shape: it already prices the bulk tier and sizes the target, and two
        # implementations would eventually disagree about the discount.
        candidates = [
            c
            for c in find_pool_candidates(db, locality=vendor.locality)
            if c.sku_name.lower() == item.sku_name.lower()
        ]
        made = materialise_pools(db, candidates)
        pool = made[0] if made else None

    if pool is None:
        return

    audience = for_locality_surge(
        db, vendor_ids=finding.vendor_ids, category=finding.category
    )
    notify_many(db, finding.detection, audience=audience, subject_id=pool.id)
