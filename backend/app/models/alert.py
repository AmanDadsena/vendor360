"""Alerts — what a detector noticed, kept so it survives being missed.

A live-only alert is worthless. A shopkeeper serving a customer, a wholesaler
driving between deliveries, anyone whose phone was locked for two hours: the
socket delivered to nobody and the thing that mattered is gone. So detections
are written here first and published second. The socket is the fast path; this
table is the record.

Exactly one of `vendor_id` / `supplier_id` is set. An alert belongs to one
principal even when the same underlying event produced several -- a shop
running out generates one alert for the shop and one for each consenting
distributor, because each reads differently and each is dismissed separately.
"""
from __future__ import annotations

import uuid

from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from ..core.db import GUID, Base, JSONColumn, TZDateTime, utcnow

SEVERITIES = ("info", "warning", "urgent")


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)

    vendor_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), nullable=True, index=True
    )
    supplier_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID, ForeignKey("suppliers.id", ondelete="CASCADE"), nullable=True, index=True
    )

    kind: Mapped[str] = mapped_column(String(20), index=True)  # anomaly|stockout|surge
    severity: Mapped[str] = mapped_column(String(10), default="info")

    title: Mapped[str] = mapped_column(String(160))
    body: Mapped[str] = mapped_column(String(400))

    # What it is about — an item, a pool, an order. Kept loose because the
    # alert's job is to get someone to the right screen, not to model the
    # subject a second time.
    subject_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True)
    payload = mapped_column(JSONColumn, default=dict)

    # Null means unread. A timestamp rather than a boolean so "when did they
    # see this" stays answerable, which matters for judging whether an alert
    # arrived in time to be acted on.
    read_at = mapped_column(TZDateTime, nullable=True)

    created_at = mapped_column(TZDateTime, default=utcnow, index=True)

    @property
    def is_read(self) -> bool:
        return self.read_at is not None


# The unread badge queries this on every socket event, so it is the hot path.
Index("ix_alert_vendor_unread", Alert.vendor_id, Alert.read_at)
Index("ix_alert_supplier_unread", Alert.supplier_id, Alert.read_at)
