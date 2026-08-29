"""Demand forecasts (TRD 3.4)."""
from __future__ import annotations

import uuid

from sqlalchemy import Date, Float, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from ..core.db import GUID, Base, JSONColumn, TZDateTime, utcnow


class Forecast(Base):
    __tablename__ = "forecasts"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(GUID, ForeignKey("vendors.id"), index=True)
    item_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("inventory_items.id", ondelete="CASCADE"), index=True
    )

    horizon_date: Mapped[Date] = mapped_column(Date, index=True)
    predicted_demand: Mapped[float] = mapped_column(Float)

    # The band the UI draws around the line. A single number would imply a
    # precision the model does not have.
    lower_bound: Mapped[float] = mapped_column(Float, default=0)
    upper_bound: Mapped[float] = mapped_column(Float, default=0)

    model_version: Mapped[str] = mapped_column(String(40), default="gbr-v1")

    # Every feature that fed this prediction, kept so a recommendation can be
    # explained after the fact rather than only at render time.
    features_used = mapped_column(JSONColumn, default=dict)

    # The single largest contributor, precomputed. This is what turns the
    # forecast into "stock 20% more milk before Friday" (UI/UX 5.5).
    driver: Mapped[str | None] = mapped_column(String(80), nullable=True)
    driver_effect: Mapped[float] = mapped_column(Float, default=0.0)

    created_at = mapped_column(TZDateTime, default=utcnow)


Index("ix_forecast_item_date", Forecast.item_id, Forecast.horizon_date, unique=True)
