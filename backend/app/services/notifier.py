"""Turning a detection into alerts and a live event.

The one place that knows the order of operations: persist, then publish. That
order is the point. Publishing first and writing second means a crash between
the two loses the record of something a user was already told about, and leaves
them unable to find it again.

Also the one place that fans a single detection out into per-principal alerts.
A shop running low produces one alert for the shop and one for each consenting
distributor, because the two read differently -- "you are running low" versus
"a shop you supply is running low" -- and each is dismissed on its own.
"""
from __future__ import annotations

import uuid

from sqlalchemy.orm import Session

from ..models import Alert, Vendor
from .audiences import for_vendor_activity
from .detectors import Detection
from .event_bus import Audience, DomainEvent, bus


def _distributor_wording(detection: Detection, store_name: str) -> tuple[str, str]:
    """The same event, said from the wholesaler's side.

    Reusing the shop's copy would put "your stock is running low" in front of
    someone whose stock it is not.
    """
    if detection.kind == "stockout":
        sku = detection.payload.get("sku_name", "an item")
        return (
            f"{store_name} is short of {sku}",
            f"{detection.body} They may need a delivery.",
        )
    if detection.kind == "anomaly":
        sku = detection.payload.get("sku_name", "an item")
        up = detection.payload.get("direction") == "up"
        return (
            f"{store_name}: {sku} is moving {'fast' if up else 'slowly'}",
            detection.body,
        )
    return detection.title, detection.body


def notify(
    db: Session,
    detection: Detection,
    *,
    vendor: Vendor,
    category: str,
    subject_id: uuid.UUID | None = None,
) -> list[Alert]:
    """Record and broadcast one detection about one shop.

    Audience — and therefore who gets an alert row at all — comes from
    `for_vendor_activity`, which applies the frozen consent scope. A
    distributor outside that scope is not merely unsubscribed from the socket;
    no alert is written for them either, so nothing leaks through the pull
    path later.
    """
    audience = for_vendor_activity(db, vendor_id=vendor.id, category=category)

    alerts: list[Alert] = [
        Alert(
            vendor_id=vendor.id,
            kind=detection.kind,
            severity=detection.severity,
            title=detection.title,
            body=detection.body,
            subject_id=subject_id,
            payload=detection.payload,
        )
    ]

    dist_title, dist_body = _distributor_wording(detection, vendor.store_name)
    for supplier_id in audience.supplier_ids:
        alerts.append(
            Alert(
                supplier_id=supplier_id,
                kind=detection.kind,
                # A supplier's copy is never urgent: it is someone else's
                # shelf, and an urgent buzz for a shop three localities away
                # is how a wholesaler learns to mute the app.
                severity="info" if detection.severity == "urgent" else detection.severity,
                title=dist_title,
                body=dist_body,
                subject_id=subject_id,
                payload={**detection.payload, "vendor_id": str(vendor.id)},
            )
        )

    db.add_all(alerts)
    db.flush()

    bus.publish(
        DomainEvent(
            kind=detection.kind,
            audience=audience,
            payload={
                **detection.payload,
                "severity": detection.severity,
                "title": detection.title,
            },
        )
    )
    return alerts


def notify_many(
    db: Session,
    detection: Detection,
    *,
    audience: Audience,
    subject_id: uuid.UUID | None = None,
) -> list[Alert]:
    """Record and broadcast a detection that belongs to several shops at once.

    Used by the surge detector, where the finding is about a locality rather
    than about one shop, and the audience was already computed as the union of
    each participant's own entitlements.
    """
    alerts = [
        Alert(
            vendor_id=vendor_id,
            kind=detection.kind,
            severity=detection.severity,
            title=detection.title,
            body=detection.body,
            subject_id=subject_id,
            payload=detection.payload,
        )
        for vendor_id in audience.vendor_ids
    ] + [
        Alert(
            supplier_id=supplier_id,
            kind=detection.kind,
            severity="info",
            title=detection.title,
            body=detection.body,
            subject_id=subject_id,
            payload=detection.payload,
        )
        for supplier_id in audience.supplier_ids
    ]

    db.add_all(alerts)
    db.flush()

    bus.publish(
        DomainEvent(
            kind=detection.kind,
            audience=audience,
            payload={**detection.payload, "title": detection.title},
        )
    )
    return alerts
