"""Wholesale distributors and mandis shown on the heatmap."""
from __future__ import annotations

import uuid

from sqlalchemy import Float, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..core.db import GUID, Base, JSONColumn, TZDateTime, utcnow


class Supplier(Base):
    __tablename__ = "suppliers"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(160))
    kind: Mapped[str] = mapped_column(String(20), default="distributor")  # distributor|mandi
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    locality: Mapped[str] = mapped_column(String(120), index=True)
    city: Mapped[str] = mapped_column(String(80), default="Pune")

    categories = mapped_column(JSONColumn, default=list)
    lead_days: Mapped[int] = mapped_column(Integer, default=2)
    min_order_value: Mapped[float] = mapped_column(Float, default=0)
    rating: Mapped[float] = mapped_column(Float, default=4.0)
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    created_at = mapped_column(TZDateTime, default=utcnow)
