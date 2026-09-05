"""The simulator, and the guards around it (TC-D**).

This is the only code in the project that writes data describing events that
did not happen, so the tests that matter are the ones about *not* running and
about staying identifiable. A simulator that quietly fabricates into a real
database, or that leaves rows nobody can distinguish from history, is worse
than no demo mode at all.
"""
from __future__ import annotations

import random
from datetime import datetime, time, timezone

import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.models import Alert, InventoryItem, Transaction, Vendor
from app.services.demo_pulse import (
    DEMO_SOURCE,
    DemoPulse,
    count_demo_sales,
    emit_one,
    is_trading_hours,
    pick_target,
    sale_quantity,
    sweep_demo_sales,
)


@pytest.fixture()
def demo_on(monkeypatch):
    """Turn the flag on for one test, and clear the settings cache after."""
    monkeypatch.setenv("DEMO_MODE", "1")
    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture()
def rng():
    # Seeded, so a test that depends on a choice is reproducible.
    return random.Random(7)


# ------------------------------------------------------------ TC-D01 guards
def test_tc_d01_refuses_to_run_unless_asked(monkeypatch):
    monkeypatch.setenv("DEMO_MODE", "0")
    get_settings.cache_clear()

    permitted, reason = DemoPulse.permitted()

    assert permitted is False
    assert "DEMO_MODE" in reason
    get_settings.cache_clear()


def test_tc_d01_refuses_a_non_sqlite_database(monkeypatch):
    """The failure actually worth designing against.

    A flag left set in a deployment must not put invented sales into a real
    shop's history.
    """
    monkeypatch.setenv("DEMO_MODE", "1")
    monkeypatch.setenv("DATABASE_URL", "postgresql://user@host/vendor360")
    get_settings.cache_clear()

    permitted, reason = DemoPulse.permitted()

    assert permitted is False
    assert "non-SQLite" in reason
    get_settings.cache_clear()


def test_tc_d01_permitted_only_with_both(demo_on):
    permitted, reason = DemoPulse.permitted()

    assert permitted is True
    assert "on" in reason


def test_tc_d01_start_declines_when_not_permitted(monkeypatch):
    monkeypatch.setenv("DEMO_MODE", "0")
    get_settings.cache_clear()

    started, _ = DemoPulse().start()

    assert started is False
    get_settings.cache_clear()


# -------------------------------------------------------------- TC-D02 marking
def test_tc_d02_every_fabricated_row_is_marked(db, vendor, milk, rng):
    """Fiction that cannot be told apart from data is the hazard."""
    assert emit_one(db, rng=rng, force=True) is True

    txn = db.scalar(select(Transaction).where(Transaction.source == DEMO_SOURCE))

    assert txn is not None
    assert txn.type == "sale"
    assert txn.qty > 0


def test_tc_d02_the_marker_is_countable(db, vendor, milk, rng):
    for _ in range(3):
        emit_one(db, rng=rng, force=True)

    assert count_demo_sales(db) == 3


def test_tc_d02_sweep_removes_only_fabricated_rows(db, vendor, milk, rng):
    """A sweep must never touch seeded or hand-entered history."""
    db.add(
        Transaction(
            vendor_id=vendor.id, item_id=milk.id, type="sale", qty=5,
            unit_value=28, source="manual",
        )
    )
    db.commit()

    emit_one(db, rng=rng, force=True)
    emit_one(db, rng=rng, force=True)

    removed = sweep_demo_sales(db)

    assert removed == 2
    assert count_demo_sales(db) == 0
    remaining = db.scalars(select(Transaction)).all()
    assert len(remaining) == 1
    assert remaining[0].source == "manual"


# ------------------------------------------------------------ TC-D03 emitting
def test_tc_d03_a_sale_reduces_the_shelf(db, vendor, milk, rng):
    before = milk.current_qty

    emit_one(db, rng=rng, force=True)
    db.refresh(milk)

    assert milk.current_qty < before
    assert milk.current_qty >= 0


def test_tc_d03_never_sells_more_than_is_there(db, vendor, milk, rng):
    milk.current_qty = 1
    db.commit()

    for _ in range(20):
        emit_one(db, rng=rng, force=True)
        db.refresh(milk)
        assert milk.current_qty >= 0


def test_tc_d03_an_empty_world_emits_nothing(db, rng):
    assert emit_one(db, rng=rng, force=True) is False


def test_tc_d03_skips_a_shelf_that_is_already_empty(db, vendor, milk, rng):
    milk.current_qty = 0
    db.commit()

    assert pick_target(db, rng=rng) is None
    assert emit_one(db, rng=rng, force=True) is False


def test_tc_d03_routes_through_the_real_detectors(db, vendor, milk, rng):
    """Not a parallel path — the same one a genuine sale takes.

    A separate code path for simulated sales would eventually drift from the
    one that matters, and the demo would stop demonstrating the product.
    """
    # Sized so any sale in the 2-9% band crosses the line, rather than
    # depending on which quantity the seeded RNG happens to pick.
    milk.current_qty = 100
    milk.reorder_point = 99
    db.commit()

    emit_one(db, rng=rng, force=True)

    alerts = db.scalars(select(Alert).where(Alert.vendor_id == vendor.id)).all()
    assert any(a.kind == "stockout" for a in alerts), (
        "a simulated sale crossing the reorder point must fire the detector"
    )


# ------------------------------------------------------------ TC-D04 realism
def test_tc_d04_piece_goods_sell_in_whole_units(db, vendor, milk, rng):
    """A shop does not sell 0.4 of a packet."""
    milk.unit = "pkt"
    milk.current_qty = 200
    db.commit()

    for _ in range(6):
        emit_one(db, rng=rng, force=True)

    for txn in db.scalars(select(Transaction).where(Transaction.source == DEMO_SOURCE)):
        assert txn.qty == int(txn.qty)


def test_tc_d04_weighed_goods_may_be_fractional(db, vendor, rng):
    item = InventoryItem(
        vendor_id=vendor.id, sku_name="Atta", category="staples",
        current_qty=100, unit="kg", unit_cost=38, unit_price=46,
        reorder_point=20,
    )
    db.add(item)
    db.commit()

    qty = sale_quantity(item, rng=rng)

    assert qty > 0
    assert round(qty, 1) == qty


def test_tc_d04_a_sale_is_a_fraction_of_the_shelf(db, vendor, rng):
    """Proportional, so a big shop's sale is bigger and nobody empties at once."""
    big = InventoryItem(
        vendor_id=vendor.id, sku_name="Rice", category="staples",
        current_qty=400, unit="kg", unit_cost=52, unit_price=62,
        reorder_point=50,
    )
    small = InventoryItem(
        vendor_id=vendor.id, sku_name="Ghee", category="staples",
        current_qty=6, unit="kg", unit_cost=600, unit_price=650,
        reorder_point=2,
    )
    db.add_all([big, small])
    db.commit()

    assert sale_quantity(big, rng=rng) > sale_quantity(small, rng=rng)
    # And never empties a shelf in one tick.
    assert sale_quantity(big, rng=rng) < big.current_qty


def test_tc_d04_quiet_outside_trading_hours(db, vendor, milk, rng):
    """Sales at 3am would look wrong and poison the weekday baseline.

    Expressed as UTC instants but reasoned about in shop time: Pune is
    UTC+5:30, so 22:00 UTC is 03:30 in the shop and 08:30 UTC is 14:00.
    """
    assert is_trading_hours(datetime(2026, 9, 4, 22, 0, tzinfo=timezone.utc)) is False
    assert is_trading_hours(datetime(2026, 9, 4, 8, 30, tzinfo=timezone.utc)) is True

    # `force` is what the tests use to bypass the clock; the loop does not.
    assert emit_one(db, rng=rng, force=False) in (True, False)


# ------------------------------------------------------------- TC-D05 routes
def test_tc_d05_status_is_readable_without_a_token(api, monkeypatch):
    """A demo control that needs a sign-in is one you cannot use mid-demo."""
    monkeypatch.setenv("DEMO_MODE", "0")
    get_settings.cache_clear()

    body = api.get("/demo/pulse").json()

    assert body["running"] is False
    assert body["available"] is False
    get_settings.cache_clear()


def test_tc_d05_start_is_refused_when_not_permitted(api, monkeypatch):
    monkeypatch.setenv("DEMO_MODE", "0")
    get_settings.cache_clear()

    response = api.post("/demo/pulse/start")

    assert response.status_code == 409
    assert "DEMO_MODE" in response.json()["detail"]
    get_settings.cache_clear()


def test_tc_d05_sweep_reports_what_it_removed(api, db, vendor, milk, rng):
    emit_one(db, rng=rng, force=True)
    emit_one(db, rng=rng, force=True)

    body = api.request("DELETE", "/demo/pulse/sales").json()

    assert body["removed"] == 2
    assert "seed.py" in body["note"]
    assert count_demo_sales(db) == 0


def test_tc_d05_health_reports_the_pulse(api):
    """Simulated activity must be discoverable from outside the process."""
    body = api.get("/health").json()

    assert "demo_pulse" in body
    assert body["demo_pulse"] in ("running", "off")


def test_tc_d05_start_runs_on_the_event_loop(api, demo_on):
    """A sync handler has no loop to create the task on, and 500s.

    Found by exercising the endpoint rather than the service: the lifespan
    call worked because it already runs on the loop, so the bug only appeared
    when something hit the route.
    """
    response = api.post("/demo/pulse/start")

    assert response.status_code == 200, response.text
    assert response.json()["running"] is True

    api.post("/demo/pulse/stop")


def test_tc_d05_start_off_loop_reports_rather_than_raises(demo_on):
    """Belt and braces: a demo control must never take the server down."""
    import asyncio

    fresh = DemoPulse()
    # No running loop in this thread.
    with pytest.raises(RuntimeError):
        asyncio.get_running_loop()

    started, reason = fresh.start()

    assert started is False
    assert "event loop" in reason


def test_tc_d06_the_demo_shop_gets_a_share_of_the_activity(db, vendor, milk):
    """Uniform across forty shops leaves the demo dashboard a still image.

    Not a majority — the heatmap has to move in several localities too, or the
    map lights one cell and the aggregate stops looking like a neighbourhood.
    """
    import uuid as _uuid

    from app.services.demo_pulse import DEMO_SHOP_BIAS

    others = []
    for i in range(9):
        v = Vendor(
            id=_uuid.uuid4(), name=f"Other{i}", store_name=f"Other{i} Stores",
            phone=f"98765900{i:02d}", language_pref="hi",
            lat=18.5, lon=73.8, locality="Aundh",
        )
        db.add(v)
        db.flush()
        db.add(
            InventoryItem(
                vendor_id=v.id, sku_name="Rice", category="staples",
                current_qty=500, unit="kg", unit_cost=52, unit_price=62,
                reorder_point=50,
            )
        )
        others.append(v)
    db.commit()

    rng = random.Random(11)
    picks = [pick_target(db, rng=rng)[0].id for _ in range(300)]
    share = picks.count(vendor.id) / len(picks)

    # The demo shop is one of ten here, so uniform would be about 0.10.
    assert share > 0.25, f"the demo shop should get a real share, got {share:.2f}"
    assert share < 0.55, "but not so much that the rest of the map goes still"
    assert len(set(picks)) > 1, "and every other shop must still get a turn"
    assert DEMO_SHOP_BIAS < 0.5
