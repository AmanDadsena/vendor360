"""Inventory items (TRD 3.2)."""
from __future__ import annotations

import uuid

from sqlalchemy import Float, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import GUID, Base, TZDateTime, utcnow


class InventoryItem(Base):
    __tablename__ = "inventory_items"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )

    sku_name: Mapped[str] = mapped_column(String(160))

    # Drives both the shelf-life default and the forecast cold-start fallback:
    # a brand-new SKU borrows its category's demand curve (TC-F04).
    category: Mapped[str] = mapped_column(String(60), default="staples", index=True)

    current_qty: Mapped[float] = mapped_column(Float, default=0)
    unit: Mapped[str] = mapped_column(String(16), default="pc")

    # Recomputed by the safety-stock service, never typed in by hand. The UI
    # shows it as a live threshold rather than a static number (UI/UX 5.4).
    reorder_point: Mapped[float] = mapped_column(Float, default=0)

    unit_cost: Mapped[float] = mapped_column(Float, default=0)
    unit_price: Mapped[float] = mapped_column(Float, default=0)

    # Null means non-perishable. Set from the category table on OCR intake,
    # which is what makes the expiry countdown automatic (PRD 5.2).
    shelf_life_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    expires_on = mapped_column(TZDateTime, nullable=True)

    # pending | synced | conflict — mirrored from the device so the vendor can
    # see which rows are still in flight.
    sync_status: Mapped[str] = mapped_column(String(16), default="synced")

    last_updated = mapped_column(TZDateTime, default=utcnow, onupdate=utcnow)
    created_at = mapped_column(TZDateTime, default=utcnow)

    vendor = relationship("Vendor", back_populates="items")
    transactions = relationship(
        "Transaction", back_populates="item", cascade="all, delete-orphan"
    )

    @property
    def is_low(self) -> bool:
        return self.current_qty <= self.reorder_point


# One vendor's catalogue is queried by name constantly — voice parsing matches
# an utterance against it on every entry.
Index("ix_item_vendor_name", InventoryItem.vendor_id, InventoryItem.sku_name)
