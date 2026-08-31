"""The distributor side: logins, catalogues, and the consent that gates them.

`Supplier` already models the organisation -- locality, lead days, minimum
order value, rating. What it never had was a way to *log in* or to say what it
sells at what price. These three tables add exactly that, and the trading
relationship that connects the two halves of the product.
"""
from __future__ import annotations

import uuid

from sqlalchemy import (
    Boolean,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import GUID, Base, JSONColumn, TZDateTime, utcnow


class DistributorUser(Base):
    """A person who can sign in on behalf of a `Supplier`.

    Modelled separately from `Supplier` rather than bolting a password onto it,
    for two reasons. `Supplier.phone` already means "the number a vendor calls",
    which is not the same thing as "the number that authenticates"; and a
    wholesaler is an organisation that can have more than one person answering
    orders, so identity belongs one level below the org.
    """

    __tablename__ = "distributor_users"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    supplier_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("suppliers.id", ondelete="CASCADE"), index=True
    )

    name: Mapped[str] = mapped_column(String(120))

    # Unique here, and additionally checked against `vendors.phone` at signup:
    # one number cannot be both a shop and a wholesaler, because the OTP flow
    # would have no way to tell which one is signing in.
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)

    language_pref: Mapped[str] = mapped_column(String(8), default="hi")
    created_at = mapped_column(TZDateTime, default=utcnow)

    supplier = relationship("Supplier", backref="users")


class CatalogEntry(Base):
    """One line of a distributor's price list.

    `pack_size` is the field everything else here depends on. Wholesalers sell
    cases, not units: a vendor who needs 12 kg of atta buys two 10 kg cases and
    receives 20. Modelling the pack explicitly is what makes minimum order
    quantities meaningful, what gives the pooling engine a threshold worth
    reaching, and what lets the app show a vendor the rounding instead of
    surprising them with it at delivery.
    """

    __tablename__ = "catalog_entries"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    supplier_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("suppliers.id", ondelete="CASCADE"), index=True
    )

    sku_name: Mapped[str] = mapped_column(String(160))
    category: Mapped[str] = mapped_column(String(60), default="staples", index=True)
    unit: Mapped[str] = mapped_column(String(16), default="pc")

    pack_size: Mapped[float] = mapped_column(Float, default=1)
    pack_price: Mapped[float] = mapped_column(Float, default=0)
    moq_packs: Mapped[int] = mapped_column(Integer, default=1)

    # Null falls back to the supplier's own lead time. A distributor who can
    # get dairy out same-day but takes three days on grain needs the override.
    lead_days: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # Null means "not tracked" rather than "none in stock", so a distributor
    # who does not want to maintain stock counts is not forced to.
    available_packs: Mapped[float | None] = mapped_column(Float, nullable=True)

    # Soft delete: historic order lines still resolve to the entry they were
    # priced from, so an order placed last month does not lose its provenance
    # when the line is withdrawn.
    active: Mapped[bool] = mapped_column(Boolean, default=True)

    updated_at = mapped_column(TZDateTime, default=utcnow, onupdate=utcnow)
    created_at = mapped_column(TZDateTime, default=utcnow)

    supplier = relationship("Supplier")

    @property
    def unit_price(self) -> float:
        """Price per selling unit, for comparing across different pack sizes."""
        if self.pack_size <= 0:
            return 0.0
        return self.pack_price / self.pack_size


# A vendor's sourcing query hits one supplier's catalogue by SKU name on every
# low-stock row, so this is the hot path.
Index("ix_catalog_supplier_sku", CatalogEntry.supplier_id, CatalogEntry.sku_name)


class VendorDistributor(Base):
    """A trading relationship, and the consent it carries.

    Shaped after `ScoreConsent`: an auditable, revocable row rather than a
    boolean, because the PRD names data-sharing hesitancy as a risk and a
    vendor deserves to be able to answer "who can see my numbers, and since
    when".

    `scope_categories` is frozen at the moment of granting. Computing it live
    from the distributor's catalogue would mean a grain wholesaler could add
    `dairy` to their price list tomorrow and silently acquire visibility into a
    shop's milk forecasts. Freezing the snapshot makes widening access an act
    the vendor has to agree to.
    """

    __tablename__ = "vendor_distributors"
    __table_args__ = (
        UniqueConstraint("vendor_id", "supplier_id", name="uq_vendor_supplier"),
    )

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )
    supplier_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("suppliers.id", ondelete="CASCADE"), index=True
    )

    # active | paused | ended. Paused keeps the history and the ledger but
    # stops the distributor seeing anything new.
    status: Mapped[str] = mapped_column(String(16), default="active")

    # The consent flag proper. False means "I will order from you, but you do
    # not get to see what I am about to need" -- a legitimate position, and one
    # the distributor intelligence must honour.
    shares_demand: Mapped[bool] = mapped_column(Boolean, default=True)

    scope_categories = mapped_column(JSONColumn, default=list)

    # 0 means cash on delivery. Snapshotted onto each order at placement so
    # renegotiating terms does not retroactively rewrite what was owed.
    credit_terms_days: Mapped[int] = mapped_column(Integer, default=0)
    credit_limit: Mapped[float] = mapped_column(Float, default=0)

    connected_at = mapped_column(TZDateTime, default=utcnow)
    revoked_at = mapped_column(TZDateTime, nullable=True)

    vendor = relationship("Vendor")
    supplier = relationship("Supplier")

    @property
    def is_active(self) -> bool:
        return self.status == "active"

    def covers(self, category: str) -> bool:
        """Whether this connection's frozen consent scope admits a category."""
        if not self.shares_demand or not self.is_active:
            return False
        return category in (self.scope_categories or [])
