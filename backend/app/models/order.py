"""Purchase orders -- the transaction that closes the prediction loop.

Everything upstream of this file computes what a shop is about to need.
Nothing until now let them act on it. An order is the object that turns a
forecast into stock on a shelf, and the delivery that completes it feeds the
next forecast, which is what makes the system improve by being used.
"""
from __future__ import annotations

import uuid

from sqlalchemy import Float, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import GUID, Base, TZDateTime, utcnow

# The lifecycle, and the only moves permitted between its states. Held here
# rather than in the service so the model and the validator cannot drift.
ORDER_STATUSES = (
    "draft",
    "placed",
    "confirmed",
    "dispatched",
    "delivered",
    "cancelled",
)

ALLOWED_TRANSITIONS: dict[str, tuple[str, ...]] = {
    "draft": ("placed", "cancelled"),
    "placed": ("confirmed", "cancelled"),
    "confirmed": ("dispatched", "cancelled"),
    "dispatched": ("delivered", "cancelled"),
    "delivered": (),
    "cancelled": (),
}

TERMINAL_STATUSES = frozenset({"delivered", "cancelled"})


class PurchaseOrder(Base):
    __tablename__ = "purchase_orders"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)

    # A short human-readable handle. The two parties settle disputes over the
    # phone, and "PO-4821" is sayable in a way a UUID is not.
    code: Mapped[str] = mapped_column(String(16), unique=True, index=True)

    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )
    supplier_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("suppliers.id", ondelete="CASCADE"), index=True
    )

    status: Mapped[str] = mapped_column(String(16), default="draft", index=True)

    placed_at = mapped_column(TZDateTime, nullable=True)
    confirmed_at = mapped_column(TZDateTime, nullable=True)
    dispatched_at = mapped_column(TZDateTime, nullable=True)
    delivered_at = mapped_column(TZDateTime, nullable=True)
    cancelled_at = mapped_column(TZDateTime, nullable=True)

    # placed_at + the lead time in force at placement, so a later change to the
    # supplier's lead days does not silently move a promise already made.
    expected_at = mapped_column(TZDateTime, nullable=True)

    payment_terms_days: Mapped[int] = mapped_column(Integer, default=0)
    amount_total: Mapped[float] = mapped_column(Float, default=0)
    amount_paid: Mapped[float] = mapped_column(Float, default=0)

    # The counterparty `BargainPool` never had. Set when a pool is accepted by
    # a distributor and splits into one order per member.
    pool_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True, index=True)

    # Minted on the device. An order placed with no signal is queued with this
    # id and replayed on reconnect; the uniqueness constraint is what makes an
    # interrupted retry land exactly once rather than twice.
    client_event_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID, unique=True, nullable=True
    )

    note: Mapped[str | None] = mapped_column(String(300), nullable=True)
    created_at = mapped_column(TZDateTime, default=utcnow)

    vendor = relationship("Vendor")
    supplier = relationship("Supplier")
    lines = relationship(
        "PurchaseOrderLine",
        back_populates="order",
        cascade="all, delete-orphan",
        order_by="PurchaseOrderLine.created_at",
    )
    events = relationship(
        "OrderEvent",
        back_populates="order",
        cascade="all, delete-orphan",
        order_by="OrderEvent.created_at",
    )

    @property
    def is_open(self) -> bool:
        return self.status not in TERMINAL_STATUSES

    @property
    def amount_due(self) -> float:
        return max(0.0, self.amount_total - self.amount_paid)


class PurchaseOrderLine(Base):
    """One SKU on an order, in three quantities.

    Ordered, confirmed and delivered are deliberately separate columns. Partial
    fulfilment is the norm in Indian wholesale, not an exception, and
    collapsing the three into one number would destroy the fill rate -- which
    is the most useful thing a vendor can know about a supplier and the reason
    `sourcing.py` can rank them at all.

    Name, unit, pack size and price are snapshotted rather than read through
    the catalogue entry, so re-pricing a line tomorrow does not rewrite what an
    order cost last month.
    """

    __tablename__ = "purchase_order_lines"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    order_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("purchase_orders.id", ondelete="CASCADE"), index=True
    )

    catalog_entry_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True)

    # The vendor's own inventory row, so a delivery restocks the right shelf
    # rather than creating a duplicate SKU. Null for something being bought for
    # the first time; the delivery handler creates the item in that case.
    item_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True)

    sku_name: Mapped[str] = mapped_column(String(160))
    category: Mapped[str] = mapped_column(String(60), default="staples")
    unit: Mapped[str] = mapped_column(String(16), default="pc")

    pack_size: Mapped[float] = mapped_column(Float, default=1)
    unit_price: Mapped[float] = mapped_column(Float, default=0)

    packs_ordered: Mapped[float] = mapped_column(Float, default=0)
    packs_confirmed: Mapped[float | None] = mapped_column(Float, nullable=True)
    packs_delivered: Mapped[float | None] = mapped_column(Float, nullable=True)

    line_total: Mapped[float] = mapped_column(Float, default=0)
    created_at = mapped_column(TZDateTime, default=utcnow)

    order = relationship("PurchaseOrder", back_populates="lines")

    @property
    def qty_ordered(self) -> float:
        return self.packs_ordered * self.pack_size

    @property
    def qty_delivered(self) -> float:
        return (self.packs_delivered or 0) * self.pack_size

    @property
    def effective_packs(self) -> float:
        """What this line currently promises, at whatever stage it has reached."""
        if self.packs_delivered is not None:
            return self.packs_delivered
        if self.packs_confirmed is not None:
            return self.packs_confirmed
        return self.packs_ordered


class OrderEvent(Base):
    """Append-only status journal.

    Exists because the two parties disagree about what happened and when, and a
    single mutable `status` column cannot settle that. It also gives the
    vendor-facing order timeline for free rather than requiring a second store.
    """

    __tablename__ = "order_events"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    order_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("purchase_orders.id", ondelete="CASCADE"), index=True
    )

    actor_role: Mapped[str] = mapped_column(String(16))  # vendor|distributor|system
    actor_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True)

    from_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    to_status: Mapped[str] = mapped_column(String(16))
    note: Mapped[str | None] = mapped_column(String(300), nullable=True)

    created_at = mapped_column(TZDateTime, default=utcnow)

    order = relationship("PurchaseOrder", back_populates="events")


class LedgerEntry(Base):
    """The khata, in its thinnest honest form.

    A charge when an order is delivered, a payment when money changes hands, an
    adjustment for everything else. There is no payment gateway: recording a
    payment is a manual act by either party, which is both what the prototype
    can support and what most of this trade actually looks like today.
    """

    __tablename__ = "ledger_entries"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )
    supplier_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("suppliers.id", ondelete="CASCADE"), index=True
    )
    order_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True, index=True)

    kind: Mapped[str] = mapped_column(String(16))  # charge|payment|adjustment
    amount: Mapped[float] = mapped_column(Float, default=0)

    due_on = mapped_column(TZDateTime, nullable=True)
    note: Mapped[str | None] = mapped_column(String(300), nullable=True)
    created_at = mapped_column(TZDateTime, default=utcnow, index=True)


Index("ix_po_vendor_status", PurchaseOrder.vendor_id, PurchaseOrder.status)
Index("ix_po_supplier_status", PurchaseOrder.supplier_id, PurchaseOrder.status)
Index("ix_ledger_pair", LedgerEntry.vendor_id, LedgerEntry.supplier_id)
