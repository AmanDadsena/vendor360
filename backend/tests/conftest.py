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
from app.models import (  # noqa: E402
    CatalogEntry,
    DistributorUser,
    InventoryItem,
    Supplier,
    Vendor,
    VendorDistributor,
)


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


# ------------------------------------------------------------ distributors
@pytest.fixture()
def supplier(db):
    """A wholesaler close enough to the test vendor to rank on distance."""
    s = Supplier(
        id=uuid.uuid4(),
        name="Shree Traders",
        kind="distributor",
        lat=18.53,
        lon=73.85,
        locality="Kothrud",
        city="Pune",
        categories=["dairy", "staples"],
        lead_days=1,
        min_order_value=500,
        rating=4.4,
        phone="9800000001",
    )
    db.add(s)
    db.commit()
    return s


@pytest.fixture()
def distributor_user(db, supplier):
    u = DistributorUser(
        id=uuid.uuid4(),
        supplier_id=supplier.id,
        name="Anil Shah",
        phone="9800000001",
    )
    db.add(u)
    db.commit()
    return u


@pytest.fixture()
def milk_listing(db, supplier):
    """Milk sold by the crate: 12 packets a case, ₹276 a case."""
    entry = CatalogEntry(
        id=uuid.uuid4(),
        supplier_id=supplier.id,
        sku_name="Milk",
        category="dairy",
        unit="pkt",
        pack_size=12,
        pack_price=276,
        moq_packs=1,
        lead_days=1,
    )
    db.add(entry)
    db.commit()
    return entry


@pytest.fixture()
def connection(db, vendor, supplier):
    """An active connection consenting to share dairy and staples demand."""
    link = VendorDistributor(
        id=uuid.uuid4(),
        vendor_id=vendor.id,
        supplier_id=supplier.id,
        status="active",
        shares_demand=True,
        scope_categories=["dairy", "staples"],
        credit_terms_days=7,
    )
    db.add(link)
    db.commit()
    return link
