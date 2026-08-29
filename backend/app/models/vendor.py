"""Vendor identity and OTP challenges (TRD 3.1, 8)."""
from __future__ import annotations

import uuid

from sqlalchemy import Boolean, Float, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.db import GUID, Base, TZDateTime, utcnow


class Vendor(Base):
    __tablename__ = "vendors"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(120))
    store_name: Mapped[str] = mapped_column(String(160))
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)

    # ISO code driving both the Bhashini locale and the app's own strings, so a
    # vendor picks a language once at onboarding and it governs everything.
    language_pref: Mapped[str] = mapped_column(String(8), default="hi")

    # Postgres would use geography(point); two floats carry the same meaning
    # portably and are all the weather lookup and heatmap grid actually need.
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lon: Mapped[float | None] = mapped_column(Float, nullable=True)
    locality: Mapped[str | None] = mapped_column(String(120), nullable=True)
    city: Mapped[str] = mapped_column(String(80), default="Pune")

    # Cached so the dashboard never blocks on a recompute. `health_score_at`
    # tells the reader how stale it is rather than leaving them to guess.
    health_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    health_score_at = mapped_column(TZDateTime, nullable=True)

    supplier_lead_days: Mapped[int] = mapped_column(Integer, default=2)
    created_at = mapped_column(TZDateTime, default=utcnow)

    items = relationship("InventoryItem", back_populates="vendor", cascade="all, delete-orphan")
    transactions = relationship("Transaction", back_populates="vendor", cascade="all, delete-orphan")


class OtpChallenge(Base):
    """A pending phone verification.

    The code is stored hashed. An attacker with read access to this table can
    still request their own OTP, but cannot harvest codes for other vendors'
    numbers mid-flight.
    """

    __tablename__ = "otp_challenges"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    phone: Mapped[str] = mapped_column(String(20), index=True)
    code_hash: Mapped[str] = mapped_column(String(128))
    expires_at = mapped_column(TZDateTime)
    consumed: Mapped[bool] = mapped_column(Boolean, default=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    created_at = mapped_column(TZDateTime, default=utcnow)


Index("ix_otp_phone_active", OtpChallenge.phone, OtpChallenge.consumed)
