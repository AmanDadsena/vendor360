"""Offline sync guarantees — Test Plan 3.4 (TC-S01..S04)."""
from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy import func, select

from app.core.db import utcnow
from app.models import ConflictAudit, InventoryItem, SyncEvent, Transaction
from app.services.sync import apply_batch


def delta_event(item_id, qty, movement="sale", seq=1, event_id=None, ts=None, **extra):
    return {
        "client_event_id": str(event_id or uuid.uuid4()),
        "local_seq": seq,
        "kind": "inventory_delta",
        "client_ts": (ts or utcnow()).isoformat(),
        "payload": {"item_id": str(item_id), "qty": qty, "movement": movement, **extra},
    }


class TestOfflineSession:
    """TC-S01 — a full offline session syncs with zero data loss."""

    def test_all_queued_events_apply(self, db, vendor, milk):
        events = [
            delta_event(milk.id, 5, "sale", seq=1, source="voice"),
            delta_event(milk.id, 3, "sale", seq=2, source="voice"),
            delta_event(milk.id, 20, "restock", seq=3, source="ocr"),
            delta_event(milk.id, 2, "wastage", seq=4, source="manual"),
        ]

        outcome = apply_batch(db, vendor_id=vendor.id, device_id="phone-a", events=events)

        assert outcome.applied == 4
        assert outcome.rejected == 0

        # 50 - 5 - 3 + 20 - 2
        assert db.get(InventoryItem, milk.id).current_qty == 60

        # Every event leaves a transaction: the audit trail is the data.
        assert db.scalar(select(func.count()).select_from(Transaction)) == 4

    def test_events_apply_in_sequence_order_not_arrival_order(self, db, vendor, milk):
        """Transport may deliver out of order; the vendor's order is what counts."""
        shuffled = [
            delta_event(milk.id, 40, "restock", seq=2),
            delta_event(milk.id, 45, "sale", seq=1),
        ]
        apply_batch(db, vendor_id=vendor.id, device_id="phone-a", events=shuffled)

        # Applied in seq order: 50 - 45 = 5, then + 40 = 45. Applied in arrival
        # order the sale would floor at 0 and the total would be wrong.
        assert db.get(InventoryItem, milk.id).current_qty == 45
        assert db.scalar(select(func.count()).select_from(ConflictAudit)) == 0


class TestConcurrentDevices:
    """TC-S02 — two devices offline on the same item; deltas must merge."""

    def test_quantity_deltas_merge_additively(self, db, vendor, milk):
        phone = [delta_event(milk.id, 12, "sale", seq=1)]
        tablet = [delta_event(milk.id, 8, "sale", seq=1)]

        apply_batch(db, vendor_id=vendor.id, device_id="phone-a", events=phone)
        apply_batch(db, vendor_id=vendor.id, device_id="tablet-b", events=tablet)

        # Both sales survive: 50 - 12 - 8. Last-write-wins on an absolute
        # quantity would have discarded one device's entire afternoon.
        assert db.get(InventoryItem, milk.id).current_qty == 30
        assert db.scalar(select(func.count()).select_from(Transaction)) == 2

    def test_scalar_conflict_surfaces_and_preserves_loser(self, db, vendor, milk):
        older = utcnow() - timedelta(hours=3)
        newer = utcnow()

        db.add(milk)
        milk.last_updated = older
        db.commit()

        winning = {
            "client_event_id": str(uuid.uuid4()),
            "local_seq": 1,
            "kind": "item_upsert",
            "client_ts": newer.isoformat(),
            "payload": {"item_id": str(milk.id), "sku_name": "Milk 500ml"},
        }
        outcome = apply_batch(
            db, vendor_id=vendor.id, device_id="phone-a", events=[winning]
        )

        assert outcome.conflicts == 1
        assert outcome.results[0].status == "applied_with_conflict"
        assert db.get(InventoryItem, milk.id).sku_name == "Milk 500ml"

        # TRD 7.2: the overwritten value is retained for vendor review.
        audit = db.scalars(select(ConflictAudit)).all()
        assert len(audit) == 1
        assert audit[0].losing_value == "Milk"
        assert audit[0].winning_value == "Milk 500ml"

    def test_stale_edit_loses_but_is_recorded(self, db, vendor, milk):
        """A device offline for hours must not overwrite a newer server value."""
        milk.sku_name = "Milk (Amul)"
        milk.last_updated = utcnow()
        db.commit()

        stale = {
            "client_event_id": str(uuid.uuid4()),
            "local_seq": 1,
            "kind": "item_upsert",
            "client_ts": (utcnow() - timedelta(hours=6)).isoformat(),
            "payload": {"item_id": str(milk.id), "sku_name": "Milk OLD NAME"},
        }
        apply_batch(db, vendor_id=vendor.id, device_id="phone-a", events=[stale])

        assert db.get(InventoryItem, milk.id).sku_name == "Milk (Amul)"
        audit = db.scalars(select(ConflictAudit)).one()
        assert audit.losing_value == "Milk OLD NAME"


class TestInterruptedSync:
    """TC-S03 — connectivity drops mid-sync; retry must not duplicate."""

    def test_replayed_batch_is_idempotent(self, db, vendor, milk):
        eid = uuid.uuid4()
        batch = [delta_event(milk.id, 10, "sale", seq=1, event_id=eid)]

        first = apply_batch(db, vendor_id=vendor.id, device_id="phone-a", events=batch)
        assert first.applied == 1
        assert db.get(InventoryItem, milk.id).current_qty == 40

        # The device never saw the response, so it retries the same batch.
        second = apply_batch(db, vendor_id=vendor.id, device_id="phone-a", events=batch)

        assert second.duplicates == 1
        assert second.applied == 0
        assert db.get(InventoryItem, milk.id).current_qty == 40
        assert db.scalar(select(func.count()).select_from(Transaction)) == 1

    def test_partial_batch_resumes_without_reapplying(self, db, vendor, milk):
        applied_id, pending_id = uuid.uuid4(), uuid.uuid4()

        apply_batch(
            db,
            vendor_id=vendor.id,
            device_id="phone-a",
            events=[delta_event(milk.id, 5, "sale", seq=1, event_id=applied_id)],
        )

        # Connection returns; the device resends the whole queue.
        resumed = apply_batch(
            db,
            vendor_id=vendor.id,
            device_id="phone-a",
            events=[
                delta_event(milk.id, 5, "sale", seq=1, event_id=applied_id),
                delta_event(milk.id, 7, "sale", seq=2, event_id=pending_id),
            ],
        )

        assert resumed.duplicates == 1
        assert resumed.applied == 1
        assert db.get(InventoryItem, milk.id).current_qty == 38  # 50 - 5 - 7

    def test_one_bad_event_does_not_sink_the_batch(self, db, vendor, milk):
        events = [
            delta_event(milk.id, 5, "sale", seq=1),
            delta_event(milk.id, 0, "sale", seq=2),               # invalid qty
            delta_event(uuid.uuid4(), 3, "sale", seq=3),          # unknown item
            delta_event(milk.id, 2, "sale", seq=4),
        ]
        outcome = apply_batch(db, vendor_id=vendor.id, device_id="phone-a", events=events)

        assert outcome.applied == 2
        assert outcome.rejected == 2
        assert db.get(InventoryItem, milk.id).current_qty == 43  # 50 - 5 - 2

        # Rejections are journalled too, so the device stops retrying them.
        assert db.scalar(select(func.count()).select_from(SyncEvent)) == 4


class TestVendorIsolation:
    """TRD 8 — no vendor may touch another vendor's rows."""

    def test_foreign_item_is_rejected(self, db, vendor, milk):
        from app.models import Vendor

        other = Vendor(
            id=uuid.uuid4(), name="Other", store_name="Other Store", phone="9999900000"
        )
        db.add(other)
        db.commit()

        outcome = apply_batch(
            db,
            vendor_id=other.id,
            device_id="phone-x",
            events=[delta_event(milk.id, 10, "sale", seq=1)],
        )

        assert outcome.rejected == 1
        assert "not found" in outcome.results[0].detail
        assert db.get(InventoryItem, milk.id).current_qty == 50  # untouched


class TestNegativeStock:
    def test_oversell_floors_at_zero_and_flags(self, db, vendor, milk):
        outcome = apply_batch(
            db,
            vendor_id=vendor.id,
            device_id="phone-a",
            events=[delta_event(milk.id, 80, "sale", seq=1)],
        )

        assert outcome.results[0].status == "applied_with_conflict"
        assert db.get(InventoryItem, milk.id).current_qty == 0

        # The sale still happened and is still recorded — only the shelf count
        # is corrected, because a negative quantity corrupts every forecast.
        assert db.scalar(select(func.count()).select_from(Transaction)) == 1
        assert db.scalar(select(func.count()).select_from(ConflictAudit)) == 1
