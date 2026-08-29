"""Shared fixtures. Each test gets a fresh in-memory database."""
from __future__ import annotations

import os
import sys
import uuid
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.db import Base  # noqa: E402
from app.models import InventoryItem, Vendor  # noqa: E402


@pytest.fixture()
def db():
    # StaticPool keeps every connection pointed at the same in-memory database;
    # without it each connection gets its own empty one and nothing persists
    # between statements.
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine, expire_on_commit=False)()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


@pytest.fixture()
def vendor(db):
    v = Vendor(
        id=uuid.uuid4(),
        name="Rakesh Kumar",
        store_name="Kumar General Stores",
        phone="9876500001",
        language_pref="hi",
        lat=18.52,
        lon=73.86,
        locality="Kothrud",
    )
    db.add(v)
    db.commit()
    return v


@pytest.fixture()
def milk(db, vendor):
    item = InventoryItem(
        id=uuid.uuid4(),
        vendor_id=vendor.id,
        sku_name="Milk",
        category="dairy",
        current_qty=50,
        unit="pkt",
        unit_cost=24,
        unit_price=28,
        reorder_point=20,
    )
    db.add(item)
    db.commit()
    return item
