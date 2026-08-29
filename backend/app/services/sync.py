"""Offline-first batch sync (TRD 7, TC-S01..S04).

The device owns its queue. Every vendor action is written to local SQLite
first, tagged with a client-generated UUID and a monotonic per-device sequence
number, and pushed here in batches when a network appears.

Three rules carry the whole design:

1. Quantities merge additively. Two devices offline for an afternoon each
   record part of the day's sales; last-write-wins on `current_qty` would throw
   one device's work away. Deltas are applied, never absolute values (TC-S02).

2. Scalar edits are last-write-wins by client timestamp, and the losing value
   is written to `ConflictAudit` rather than discarded. TRD 7.2 forbids a
   silent overwrite.

3. `client_event_id` makes application idempotent. A batch interrupted halfway
   is retried whole, and events already applied are reported as duplicates
   instead of being applied twice (TC-S03).
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.db import utcnow
from ..models import ConflictAudit, InventoryItem, SyncEvent, Transaction

# Fields a device may edit that are not quantities. Everything here resolves by
# last-write-wins; anything not listed is server-owned and silently ignored,
# so a stale or malicious client cannot rewrite a computed reorder point.
SCALAR_FIELDS = {"sku_name", "category", "unit", "unit_cost", "unit_price"}

MOVEMENT_SIGN = {"sale": -1.0, "wastage": -1.0, "restock": 1.0}


@dataclass
class EventResult:
    client_event_id: str
    status: str           # applied | applied_with_conflict | rejected | duplicate
    detail: str = ""
    item_id: str | None = None


@dataclass
class SyncOutcome:
    results: list[EventResult] = field(default_factory=list)
    applied: int = 0
    duplicates: int = 0
    conflicts: int = 0
    rejected: int = 0

    def record(self, result: EventResult) -> None:
        self.results.append(result)
        match result.status:
            case "applied":
                self.applied += 1
            case "applied_with_conflict":
                self.applied += 1
                self.conflicts += 1
            case "duplicate":
                self.duplicates += 1
            case _:
                self.rejected += 1


def _coerce_uuid(value) -> uuid.UUID | None:
    try:
        return value if isinstance(value, uuid.UUID) else uuid.UUID(str(value))
    except (ValueError, AttributeError, TypeError):
        return None


def apply_batch(
    db: Session,
    *,
    vendor_id: uuid.UUID,
    device_id: str,
    events: list[dict],
) -> SyncOutcome:
    """Apply a batch of queued device events and report per-event status.

    Events are sorted by `local_seq` before application so they replay in the
    order the vendor performed them, regardless of the order the transport
    delivered them in.
    """
    outcome = SyncOutcome()
    ordered = sorted(events, key=lambda e: e.get("local_seq", 0))

    for event in ordered:
        event_id = _coerce_uuid(event.get("client_event_id"))
        if event_id is None:
            outcome.record(
                EventResult(
                    client_event_id=str(event.get("client_event_id")),
                    status="rejected",
                    detail="missing or malformed client_event_id",
                )
            )
            continue

        # Idempotency gate. Checked before any mutation so a retried batch
        # cannot double-apply even partially.
        already = db.scalar(
            select(SyncEvent).where(SyncEvent.client_event_id == event_id)
        )
        if already is not None:
            outcome.record(
                EventResult(
                    client_event_id=str(event_id),
                    status="duplicate",
                    detail="already applied",
                    item_id=str(already.payload.get("item_id"))
                    if isinstance(already.payload, dict)
                    else None,
                )
            )
            continue

        kind = event.get("kind", "inventory_delta")
        payload = event.get("payload") or {}
        client_ts = _parse_ts(event.get("client_ts"))

        try:
            if kind == "inventory_delta":
                result = _apply_delta(db, vendor_id, event_id, payload, client_ts)
            elif kind == "item_upsert":
                result = _apply_upsert(
                    db, vendor_id, device_id, event_id, payload, client_ts
                )
            else:
                result = EventResult(
                    client_event_id=str(event_id),
                    status="rejected",
                    detail=f"unknown event kind: {kind}",
                )
        except Exception as exc:  # noqa: BLE001 - one bad event must not sink the batch
            result = EventResult(
                client_event_id=str(event_id),
                status="rejected",
                detail=f"{type(exc).__name__}: {exc}",
            )

        # Journal every event, including rejections: the device needs a durable
        # answer for each queued item, and a rejection with no record would be
        # retried forever.
        db.add(
            SyncEvent(
                client_event_id=event_id,
                vendor_id=vendor_id,
                device_id=device_id,
                local_seq=int(event.get("local_seq", 0)),
                kind=kind,
                payload=payload,
                status=result.status,
                detail=result.detail[:300] if result.detail else None,
                client_ts=client_ts,
            )
        )
        outcome.record(result)

    db.commit()
    return outcome


def _parse_ts(value) -> datetime:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return utcnow()


def _apply_delta(
    db: Session,
    vendor_id: uuid.UUID,
    event_id: uuid.UUID,
    payload: dict,
    client_ts: datetime,
) -> EventResult:
    """Apply one stock movement as a signed delta.

    The device sends a movement and a magnitude, never a resulting quantity.
    That is what makes concurrent offline edits mergeable: two deltas commute,
    two absolute values do not.
    """
    item_id = _coerce_uuid(payload.get("item_id"))
    if item_id is None:
        return EventResult(str(event_id), "rejected", "missing item_id")

    item = db.scalar(
        select(InventoryItem).where(
            InventoryItem.id == item_id, InventoryItem.vendor_id == vendor_id
        )
    )
    if item is None:
        # Scoped by vendor_id, so this also covers an attempt to touch another
        # vendor's row -- indistinguishable from "not found", which is the
        # correct thing to leak.
        return EventResult(str(event_id), "rejected", "item not found for this vendor")

    movement = payload.get("movement", "sale")
    sign = MOVEMENT_SIGN.get(movement)
    if sign is None:
        return EventResult(str(event_id), "rejected", f"unknown movement: {movement}")

    qty = float(payload.get("qty", 0))
    if qty <= 0:
        return EventResult(str(event_id), "rejected", "qty must be positive")

    before = item.current_qty
    item.current_qty = before + (sign * qty)

    detail = ""
    status = "applied"

    # Stock going negative means the device's view of the shelf disagreed with
    # the server's. The sale is real and is kept -- it happened -- but the
    # quantity is floored and flagged, because a negative shelf count would
    # corrupt every downstream forecast and reorder point.
    if item.current_qty < 0:
        detail = (
            f"stock floored at 0 (had {before:g}, {movement} of {qty:g} "
            f"would give {item.current_qty:g})"
        )
        item.current_qty = 0.0
        status = "applied_with_conflict"
        db.add(
            ConflictAudit(
                vendor_id=vendor_id,
                item_id=item.id,
                field="current_qty",
                losing_value=f"{before + (sign * qty):g}",
                winning_value="0",
                losing_device=payload.get("device_id", "unknown"),
            )
        )

    item.last_updated = utcnow()
    item.sync_status = "synced"

    db.add(
        Transaction(
            vendor_id=vendor_id,
            item_id=item.id,
            type=movement,
            qty=qty,
            unit_value=float(payload.get("unit_value", item.unit_price or 0)),
            source=payload.get("source", "manual"),
            confidence=float(payload.get("confidence", 1.0)),
            raw_text=payload.get("raw_text"),
            occurred_at=client_ts,
        )
    )

    return EventResult(str(event_id), status, detail, item_id=str(item.id))


def _apply_upsert(
    db: Session,
    vendor_id: uuid.UUID,
    device_id: str,
    event_id: uuid.UUID,
    payload: dict,
    client_ts: datetime,
) -> EventResult:
    """Create or edit an item's scalar fields, last-write-wins."""
    item_id = _coerce_uuid(payload.get("item_id"))
    if item_id is None:
        return EventResult(str(event_id), "rejected", "missing item_id")

    item = db.scalar(
        select(InventoryItem).where(
            InventoryItem.id == item_id, InventoryItem.vendor_id == vendor_id
        )
    )

    if item is None:
        # The device minted this UUID offline, so creation is an upsert rather
        # than an error -- the row simply has not reached the server yet.
        item = InventoryItem(
            id=item_id,
            vendor_id=vendor_id,
            sku_name=payload.get("sku_name", "Unnamed item"),
            category=payload.get("category", "staples"),
            unit=payload.get("unit", "pc"),
            current_qty=float(payload.get("current_qty", 0)),
            unit_cost=float(payload.get("unit_cost", 0)),
            unit_price=float(payload.get("unit_price", 0)),
            sync_status="synced",
        )
        db.add(item)
        return EventResult(str(event_id), "applied", "created", item_id=str(item.id))

    conflicts: list[str] = []

    # A device that has been offline may carry an older edit than one already
    # applied. Comparing client timestamps -- not arrival order -- is what makes
    # the winner the genuinely later edit.
    server_ts = item.last_updated or client_ts
    incoming_is_newer = client_ts >= server_ts

    for field_name in SCALAR_FIELDS:
        if field_name not in payload:
            continue
        incoming = payload[field_name]
        current = getattr(item, field_name)
        if incoming == current:
            continue

        if incoming_is_newer:
            setattr(item, field_name, incoming)
            losing, winning = current, incoming
        else:
            losing, winning = incoming, current

        conflicts.append(field_name)
        db.add(
            ConflictAudit(
                vendor_id=vendor_id,
                item_id=item.id,
                field=field_name,
                losing_value=str(losing)[:300],
                winning_value=str(winning)[:300],
                losing_device=device_id if incoming_is_newer else "server",
            )
        )

    if incoming_is_newer:
        item.last_updated = client_ts
    item.sync_status = "synced"

    if conflicts:
        return EventResult(
            str(event_id),
            "applied_with_conflict",
            f"resolved: {', '.join(conflicts)}",
            item_id=str(item.id),
        )
    return EventResult(str(event_id), "applied", item_id=str(item.id))
