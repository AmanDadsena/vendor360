"""The other half of the khata: what the neighbourhood owes the shop.

`LedgerEntry` records what the shop owes its distributor. This records what
its customers owe it — the book a kirana actually keeps on paper, and the one
that says whether a shop with good sales is actually holding any cash.

A balance is never stored. It is the sum of what was taken minus what came
back, derived on every read, because a stored total and a list of entries are
two sources of truth that drift — and the entries are the ones a customer will
argue with at the counter.
"""
from __future__ import annotations

import uuid

from sqlalchemy import Float, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import GUID, Base, TZDateTime, utcnow

#: Goods taken on credit, and money handed back.
UDHAAR_KINDS = ("credit", "payment")


class Customer(Base):
    """Someone who buys on credit from one shop.

    Scoped to a vendor rather than shared: two shops on the same street may
    both know a "Suresh", and neither should see the other's book.
    """

    __tablename__ = "customers"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )

    name: Mapped[str] = mapped_column(String(120))

    # Nullable on purpose. A paper khata says "Suresh, corner house", and a
    # form that demands a mobile number before it will record a debt is a form
    # the shopkeeper stops using.
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)

    note: Mapped[str | None] = mapped_column(String(160), nullable=True)
    created_at = mapped_column(TZDateTime, default=utcnow)

    entries = relationship(
        "UdhaarEntry",
        back_populates="customer",
        cascade="all, delete-orphan",
    )


class UdhaarEntry(Base):
    """One line of the customer's page: goods taken, or money returned."""

    __tablename__ = "udhaar_entries"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )
    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("customers.id", ondelete="CASCADE"), index=True
    )

    # credit | payment
    kind: Mapped[str] = mapped_column(String(16), index=True)

    #: Always positive. Direction lives in [kind], so a sign error cannot turn
    #: a payment into a debt.
    amount: Mapped[float] = mapped_column(Float)

    note: Mapped[str | None] = mapped_column(String(160), nullable=True)

    #: The sale this credit was for, when it came from one. Nullable: most
    #: entries are written straight into the book.
    transaction_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True)

    occurred_at = mapped_column(TZDateTime, default=utcnow, index=True)
    created_at = mapped_column(TZDateTime, default=utcnow)

    customer = relationship("Customer", back_populates="entries")
