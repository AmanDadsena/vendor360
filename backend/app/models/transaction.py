"""Transactions, the sync journal, and the conflict audit (TRD 3.3, 7)."""
from __future__ import annotations

import uuid

from sqlalchemy import Float, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import GUID, Base, JSONColumn, TZDateTime, utcnow


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )
    item_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("inventory_items.id", ondelete="CASCADE"), index=True
    )

    # sale | restock | wastage. Wastage is its own type rather than a negative
    # sale, because the Health Score has to tell spoilage from turnover.
    type: Mapped[str] = mapped_column(String(16), index=True)
    qty: Mapped[float] = mapped_column(Float)
    unit_value: Mapped[float] = mapped_column(Float, default=0)

    # voice | ocr | manual | seed — kept so ASR and OCR accuracy can be
    # measured against manual entry on real usage.
    source: Mapped[str] = mapped_column(String(16), default="manual")

    # ASR/OCR extraction confidence. 1.0 for manual entry.
    confidence: Mapped[float] = mapped_column(Float, default=1.0)
    raw_text: Mapped[str | None] = mapped_column(String(500), nullable=True)

    occurred_at = mapped_column(TZDateTime, default=utcnow, index=True)
    created_at = mapped_column(TZDateTime, default=utcnow)

    vendor = relationship("Vendor", back_populates="transactions")
    item = relationship("InventoryItem", back_populates="transactions")


class SyncEvent(Base):
    """One queued offline action, keyed by the id the device generated.

    `client_event_id` is the whole idempotency story: a batch interrupted
    mid-flight is retried wholesale, and events already applied are recognised
    and skipped rather than applied twice (TC-S03).
    """

    __tablename__ = "sync_events"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    client_event_id: Mapped[uuid.UUID] = mapped_column(GUID, unique=True, index=True)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )
    device_id: Mapped[str] = mapped_column(String(64))

    # Monotonic per device. The server orders a batch by this, so events
    # replay in the sequence the vendor actually performed them.
    local_seq: Mapped[int] = mapped_column(Integer)

    kind: Mapped[str] = mapped_column(String(32))
    payload = mapped_column(JSONColumn)

    # applied | applied_with_conflict | rejected | duplicate
    status: Mapped[str] = mapped_column(String(24), default="applied")
    detail: Mapped[str | None] = mapped_column(String(300), nullable=True)

    client_ts = mapped_column(TZDateTime)
    applied_at = mapped_column(TZDateTime, default=utcnow)


class ConflictAudit(Base):
    """The losing side of a last-write-wins resolution.

    TRD 7.2 requires the overwritten edit to survive for vendor review; a
    silent overwrite is the one outcome the design forbids.
    """

    __tablename__ = "conflict_audits"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )
    item_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True)
    field: Mapped[str] = mapped_column(String(60))
    losing_value: Mapped[str] = mapped_column(String(300))
    winning_value: Mapped[str] = mapped_column(String(300))
    losing_device: Mapped[str] = mapped_column(String(64))
    reviewed: Mapped[bool] = mapped_column(default=False)
    created_at = mapped_column(TZDateTime, default=utcnow)


Index("ix_txn_vendor_time", Transaction.vendor_id, Transaction.occurred_at)
Index("ix_sync_vendor_device", SyncEvent.vendor_id, SyncEvent.device_id, SyncEvent.local_seq)
