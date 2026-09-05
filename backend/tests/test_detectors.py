"""Live detection (TC-R**).

The edge-trigger and baseline cases are the ones that matter. A stockout alert
that fires on every sale past the line, or an anomaly detector that flags every
Saturday, is worse than no detector at all -- people learn to dismiss it, and
then miss the one that mattered.
"""
from __future__ import annotations

import uuid
from datetime import datetime, time, timedelta, timezone

import pytest
from sqlalchemy import select

from app.core.db import utcnow
from app.models import BargainPool, InventoryItem, Transaction, Vendor
from app.services.detectors import (
    ANOMALY_Z,
    SHOP_UTC_OFFSET_HOURS,
    shop_hour,
    MIN_RELATIVE_SPREAD,
    MIN_DAY_FRACTION,
    day_fraction,
    detect_anomaly,
    detect_stockout,
    detect_surge,
)


def _at_shop_hour(hour: float, *, offset_days: int = 0) -> datetime:
    """A UTC instant that is `hour` on the *shop's* clock.

    Fixtures name shop time because that is what the detectors reason about.
    Writing them in UTC is what let the timezone bug hide: a test asserting
    "2pm" meant 19:30 in Pune, and nothing said so.
    """
    utc_hour = (hour - SHOP_UTC_OFFSET_HOURS) % 24
    day = datetime.now(timezone.utc).date() - timedelta(days=offset_days)
    return datetime.combine(
        day, time(int(utc_hour), int((utc_hour % 1) * 60)), timezone.utc
    )


def _midday(offset_days: int = 0) -> datetime:
    """2pm on the shop's clock, so tests do not drift with the wall clock."""
    return _at_shop_hour(14, offset_days=offset_days)


def _sell(db, item, qty, *, when):
    db.add(
        Transaction(
            vendor_id=item.vendor_id,
            item_id=item.id,
            type="sale",
            qty=qty,
            unit_value=item.unit_price,
            source="seed",
            occurred_at=when,
        )
    )


def _weekday_history(db, item, *, per_week: float, weeks: int = 8):
    """The same weekday, `weeks` times, at the same hour."""
    for week in range(1, weeks + 1):
        _sell(db, item, per_week, when=_midday(offset_days=7 * week) - timedelta(hours=2))
    db.commit()


# ----------------------------------------------------------- TC-R01 stockout
def test_tc_r01_fires_on_the_crossing(db, milk):
    milk.reorder_point = 20
    milk.current_qty = 18

    found = detect_stockout(milk, previous_qty=25)

    assert found is not None
    assert found.kind == "stockout"
    assert "running low" in found.title
    assert found.payload["empty"] is False


def test_tc_r01_does_not_fire_again_once_already_below(db, milk):
    """Edge-triggered. Level-triggered would re-fire on every later sale."""
    milk.reorder_point = 20
    milk.current_qty = 15

    assert detect_stockout(milk, previous_qty=18) is None
    assert detect_stockout(milk, previous_qty=16) is None


def test_tc_r01_silent_while_stock_is_healthy(db, milk):
    milk.reorder_point = 20
    milk.current_qty = 40

    assert detect_stockout(milk, previous_qty=45) is None


def test_tc_r01_an_empty_shelf_is_urgent_and_says_so(db, milk):
    milk.reorder_point = 20
    milk.current_qty = 0

    # From above the line straight to empty — one sale can do that.
    found = detect_stockout(milk, previous_qty=25)

    assert found.severity == "urgent"
    assert "finished" in found.title
    assert found.payload["empty"] is True


def test_tc_r01_an_item_with_no_reorder_point_cannot_cross_one(db, milk):
    milk.reorder_point = 0
    milk.current_qty = 0

    assert detect_stockout(milk, previous_qty=10) is None


# --------------------------------------------------------- TC-R04 shop clock
def test_tc_r04_the_trading_day_is_the_shops_clock_not_utc():
    """The bug this pins was silent and total.

    DAY_OPENS/DAY_CLOSES describe a Pune shop's day, but the hour was read
    from UTC. Pune is UTC+5:30, so the 07:00-21:00 window landed at
    01:30-15:30 UTC: the anomaly detector stayed quiet through every Pune
    morning and woke through the night, and nothing anywhere said so.
    """
    assert SHOP_UTC_OFFSET_HOURS == 5.5

    # 04:47 UTC is 10:17 in Pune -- mid-morning, a shop's busiest hours.
    morning = datetime(2026, 9, 5, 4, 47, tzinfo=timezone.utc)
    assert shop_hour(morning) == pytest.approx(10.28, abs=0.02)
    assert day_fraction(morning) > 0, "a Pune shop is open and selling at 10am"

    # 23:00 UTC is 04:30 in Pune -- shut.
    night = datetime(2026, 9, 5, 23, 0, tzinfo=timezone.utc)
    assert shop_hour(night) == pytest.approx(4.5)
    assert day_fraction(night) == 0


def test_tc_r04_the_shop_clock_wraps_past_midnight():
    """An offset that pushes past midnight lands at the start of the day."""
    late = datetime(2026, 9, 5, 20, 0, tzinfo=timezone.utc)  # 01:30 Pune

    assert shop_hour(late) == pytest.approx(1.5)
    assert 0 <= shop_hour(late) < 24


def test_tc_r04_day_fraction_runs_zero_to_one_across_the_shop_day():
    def at(utc_hour: float) -> float:
        h = int(utc_hour)
        m = int((utc_hour - h) * 60)
        return day_fraction(datetime(2026, 9, 5, h, m, tzinfo=timezone.utc))

    # 07:00 Pune == 01:30 UTC, 21:00 Pune == 15:30 UTC.
    assert at(1.5) == pytest.approx(0.0)
    assert at(8.5) == pytest.approx(0.5, abs=0.02)
    assert at(15.5) == pytest.approx(1.0)


# ------------------------------------------------------------ TC-R02 anomaly
def test_tc_r02_quiet_before_enough_of_the_day_has_passed(db, milk):
    """At 8am one early customer looks like a surge. Silence is the honest output."""
    early = _at_shop_hour(8)  # 08:00 in the shop, barely open
    assert day_fraction(early) < MIN_DAY_FRACTION
    assert detect_anomaly(db, milk, now=early) is None


def test_tc_r02_quiet_without_enough_history(db, milk):
    """Two samples cannot produce a standard deviation worth acting on."""
    _sell(db, milk, 10, when=_midday(offset_days=7))
    _sell(db, milk, 10, when=_midday(offset_days=14))
    db.commit()

    assert detect_anomaly(db, milk, now=_midday()) is None


def test_tc_r02_flags_a_genuine_spike(db, milk):
    _weekday_history(db, milk, per_week=10)
    # Today, well past a normal day's whole total by mid-afternoon.
    _sell(db, milk, 40, when=_midday() - timedelta(hours=1))
    db.commit()

    found = detect_anomaly(db, milk, now=_midday())

    assert found is not None
    assert found.payload["direction"] == "up"
    assert found.payload["ratio"] > 1
    assert abs(found.payload["z"]) >= ANOMALY_Z


def test_tc_r02_a_normal_day_is_not_an_anomaly(db, milk):
    _weekday_history(db, milk, per_week=10)
    # 2pm is halfway through a 07:00-21:00 shop day, so half a normal day's
    # sales is exactly ordinary.
    _sell(db, milk, 5, when=_midday() - timedelta(hours=1))
    db.commit()

    assert detect_anomaly(db, milk, now=_at_shop_hour(14)) is None


def test_tc_r02_flags_a_collapse_as_information_not_alarm(db, milk):
    _weekday_history(db, milk, per_week=40)
    _sell(db, milk, 0.5, when=_midday() - timedelta(hours=1))
    db.commit()

    found = detect_anomaly(db, milk, now=_midday())

    assert found is not None
    assert found.payload["direction"] == "down"
    # Nothing is on fire when sales are slow; it is worth knowing, not buzzing.
    assert found.severity == "info"


def test_tc_r02_reports_low_confidence_on_thin_history(db, milk):
    _weekday_history(db, milk, per_week=10, weeks=4)
    _sell(db, milk, 40, when=_midday() - timedelta(hours=1))
    db.commit()

    found = detect_anomaly(db, milk, now=_midday())

    assert found is not None
    assert found.payload["confidence"] == "low"


def test_tc_r02_compares_like_weekdays(db, milk):
    """A Saturday must be judged against Saturdays.

    The seeded world gives weekends a 35% lift, so a flat trailing mean would
    flag every Saturday as a surge and the detector would be noise by design.
    """
    _weekday_history(db, milk, per_week=10)
    # Half a normal day's sales, halfway through the day.
    _sell(db, milk, 5, when=_midday() - timedelta(hours=1))
    db.commit()

    assert detect_anomaly(db, milk, now=_midday()) is None

    # The same absolute number would be extraordinary against a smaller baseline.
    other = InventoryItem(
        vendor_id=milk.vendor_id, sku_name="Ghee", category="staples",
        current_qty=50, unit="kg", unit_cost=600, unit_price=650, reorder_point=10,
    )
    db.add(other)
    db.commit()
    _weekday_history(db, other, per_week=0.5)
    _sell(db, other, 5, when=_midday() - timedelta(hours=1))
    db.commit()

    assert detect_anomaly(db, other, now=_midday()) is not None


# -------------------------------------------------------------- TC-R03 surge
def _short_shop(db, name, phone, sku, *, locality="Kothrud"):
    vendor = Vendor(
        id=uuid.uuid4(), name=name, store_name=f"{name} Stores", phone=phone,
        language_pref="hi", lat=18.51, lon=73.81, locality=locality,
    )
    db.add(vendor)
    db.commit()

    item = InventoryItem(
        vendor_id=vendor.id, sku_name=sku, category="dairy",
        current_qty=2, unit="pkt", unit_cost=24, unit_price=28,
        reorder_point=20, last_updated=utcnow(),
    )
    db.add(item)
    db.commit()
    return vendor, item


def test_tc_r03_three_short_shops_in_a_locality_is_a_surge(db):
    for i in range(3):
        _short_shop(db, f"Shop{i}", f"98765400{i:02d}", "Milk")

    found = detect_surge(db, sku_name="Milk", locality="Kothrud")

    assert found is not None
    assert found.detection.kind == "surge"
    assert found.detection.payload["shop_count"] == 3
    assert len(found.vendor_ids) == 3
    assert found.detection.payload["shortfall"] > 0


def test_tc_r03_two_is_not_a_surge(db):
    """Same threshold pooling.py already uses: below three it is a coincidence."""
    for i in range(2):
        _short_shop(db, f"Shop{i}", f"98765410{i:02d}", "Milk")

    assert detect_surge(db, sku_name="Milk", locality="Kothrud") is None


def test_tc_r03_a_different_locality_does_not_count(db):
    _short_shop(db, "A", "9876542001", "Milk")
    _short_shop(db, "B", "9876542002", "Milk")
    _short_shop(db, "C", "9876542003", "Milk", locality="Aundh")

    assert detect_surge(db, sku_name="Milk", locality="Kothrud") is None


def test_tc_r03_a_different_sku_does_not_count(db):
    _short_shop(db, "A", "9876543001", "Milk")
    _short_shop(db, "B", "9876543002", "Milk")
    _short_shop(db, "C", "9876543003", "Curd")

    assert detect_surge(db, sku_name="Milk", locality="Kothrud") is None


def test_tc_r03_a_stale_shortage_falls_out_of_the_window(db):
    """Three shops short over three weeks is not the same event."""
    for i in range(3):
        _, item = _short_shop(db, f"Shop{i}", f"98765440{i:02d}", "Milk")
        item.last_updated = utcnow() - timedelta(days=3)
    db.commit()

    assert detect_surge(db, sku_name="Milk", locality="Kothrud") is None
