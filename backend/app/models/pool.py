"""Multi-vendor collective bargaining (PRD 5.1 P1, TC-B01/B02)."""
from __future__ import annotations

import uuid

from sqlalchemy import Boolean, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import GUID, Base, TZDateTime, utcnow


class BargainPool(Base):
    """A shortage several nearby vendors share, batched into one order."""

    __tablename__ = "bargain_pools"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    sku_name: Mapped[str] = mapped_column(String(160), index=True)
    category: Mapped[str] = mapped_column(String(60), default="staples")
    unit: Mapped[str] = mapped_column(String(16), default="pc")
    locality: Mapped[str] = mapped_column(String(120), index=True)

    target_qty: Mapped[float] = mapped_column(Float, default=0)
    committed_qty: Mapped[float] = mapped_column(Float, default=0)

    base_unit_price: Mapped[float] = mapped_column(Float, default=0)

    # Realised only once committed_qty clears target_qty, which is what gives
    # vendors a reason to pool rather than order alone.
    bulk_unit_price: Mapped[float] = mapped_column(Float, default=0)

    supplier_id: Mapped[uuid.UUID | None] = mapped_column(GUID, nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="open")  # open|locked|fulfilled
    closes_at = mapped_column(TZDateTime)
    created_at = mapped_column(TZDateTime, default=utcnow)

    members = relationship("PoolMember", back_populates="pool", cascade="all, delete-orphan")

    @property
    def progress(self) -> float:
        if self.target_qty <= 0:
            return 0.0
        return min(1.0, self.committed_qty / self.target_qty)

    @property
    def savings_per_unit(self) -> float:
        return max(0.0, self.base_unit_price - self.bulk_unit_price)


class PoolMember(Base):
    __tablename__ = "pool_members"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    pool_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("bargain_pools.id", ondelete="CASCADE"), index=True
    )
    vendor_id: Mapped[uuid.UUID] = mapped_column(GUID, ForeignKey("vendors.id"), index=True)
    qty: Mapped[float] = mapped_column(Float, default=0)

    # Opting out leaves the row in place so the pool total can be recomputed
    # and the vendor's own order proceeds individually (TC-B02).
    opted_out: Mapped[bool] = mapped_column(Boolean, default=False)
    joined_at = mapped_column(TZDateTime, default=utcnow)

    pool = relationship("BargainPool", back_populates="members")
