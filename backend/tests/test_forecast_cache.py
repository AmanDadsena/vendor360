"""The persisted forecast cache (TC-FC**).

The window-alignment cases here exist because of a real bug: the cache wrote
faithfully and read back nothing, because it queried `today..today+N-1` while
`forecast_item` stores `today+1..today+N`. Every call missed, no error was
raised, and the only symptom was that the endpoint stayed slow.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select

from app.core.db import utcnow
from app.models import Forecast, InventoryItem, Transaction
from app.services import forecast_cache
from app.services.forecasting import forecast_item


def _history(db, item, *, per_day=8.0, days=40):
    for offset in range(days, 0, -1):
        db.add(
            Transaction(
                vendor_id=item.vendor_id,
                item_id=item.id,
                type="sale",
                qty=per_day,
                unit_value=item.unit_price,
                source="seed",
                occurred_at=utcnow() - timedelta(days=offset),
            )
        )
    db.commit()
    return [
        (t.occurred_at.date(), float(t.qty))
        for t in db.scalars(
            select(Transaction).where(Transaction.item_id == item.id)
        )
    ]


def _today():
    return datetime.now(timezone.utc).date()


# --------------------------------------------------- TC-FC01 window alignment
def test_tc_fc01_stored_horizon_starts_tomorrow_not_today(db, vendor, milk):
    """Today is a partial observation, not a prediction — so it is not stored."""
    history = _history(db, milk)
    result = forecast_item(
        item_id=str(milk.id),
        sku_name=milk.sku_name,
        category_key=milk.category,
        history=history,
        horizon_days=7,
    )
    forecast_cache.store(db, vendor_id=vendor.id, item_id=milk.id, result=result)
    db.commit()

    dates = sorted(
        r.horizon_date
        for r in db.scalars(select(Forecast).where(Forecast.item_id == milk.id))
    )

    assert len(dates) == 7
    assert dates[0] == _today() + timedelta(days=1), 'the horizon opens tomorrow'
    assert dates[-1] == _today() + timedelta(days=7)


def test_tc_fc01_read_uses_the_same_window_it_wrote(db, vendor, milk):
    """The regression. A one-day skew makes every read a silent miss."""
    history = _history(db, milk)
    forecast_cache.total_for(db, milk, horizon_days=7, history=history)
    db.commit()

    cached = forecast_cache.read(db, item_id=milk.id, horizon_days=7)

    assert cached is not None, 'the window written must be the window read'
    assert len(cached) == 7


def test_tc_fc02_a_second_read_does_not_refit(db, vendor, milk, monkeypatch):
    """The whole point: the model is fitted once a day, not once a request."""
    history = _history(db, milk)
    forecast_cache.total_for(db, milk, horizon_days=7, history=history)
    db.commit()

    calls = {"n": 0}
    real = forecast_cache.forecast_item

    def counting(**kwargs):
        calls["n"] += 1
        return real(**kwargs)

    monkeypatch.setattr(forecast_cache, "forecast_item", counting)

    for _ in range(5):
        forecast_cache.total_for(db, milk, horizon_days=7, history=history)

    assert calls["n"] == 0


def test_tc_fc02_the_cached_total_matches_the_computed_one(db, vendor, milk):
    history = _history(db, milk)

    fresh = forecast_cache.total_for(db, milk, horizon_days=7, history=history)
    db.commit()
    cached = forecast_cache.total_for(db, milk, horizon_days=7, history=history)

    assert cached == pytest.approx(fresh)


# ------------------------------------------------------- TC-FC03 completeness
def test_tc_fc03_a_shorter_stored_horizon_is_not_a_hit(db, vendor, milk):
    """Half a week's demand reported as a week's is worse than a slow answer."""
    history = _history(db, milk)
    forecast_cache.total_for(db, milk, horizon_days=7, history=history)
    db.commit()

    assert forecast_cache.read(db, item_id=milk.id, horizon_days=7) is not None
    assert forecast_cache.read(db, item_id=milk.id, horizon_days=14) is None


def test_tc_fc03_a_longer_horizon_recomputes_and_covers_the_shorter_one(
    db, vendor, milk
):
    history = _history(db, milk)
    forecast_cache.total_for(db, milk, horizon_days=7, history=history)
    db.commit()

    forecast_cache.total_for(db, milk, horizon_days=14, history=history)
    db.commit()

    assert forecast_cache.read(db, item_id=milk.id, horizon_days=14) is not None
    assert forecast_cache.read(db, item_id=milk.id, horizon_days=7) is not None


# ---------------------------------------------------------- TC-FC04 staleness
def test_tc_fc04_yesterdays_forecast_is_stale(db, vendor, milk):
    """Inputs change once a day, so the cache expires once a day."""
    history = _history(db, milk)
    forecast_cache.total_for(db, milk, horizon_days=7, history=history)
    db.commit()

    for row in db.scalars(select(Forecast).where(Forecast.item_id == milk.id)):
        row.created_at = utcnow() - timedelta(days=1, hours=1)
    db.commit()

    assert forecast_cache.read(db, item_id=milk.id, horizon_days=7) is None


def test_tc_fc04_recomputing_replaces_rather_than_duplicates(db, vendor, milk):
    history = _history(db, milk)

    for _ in range(3):
        forecast_cache.total_for(db, milk, horizon_days=7, history=history)
        db.commit()
        # Force the next call to miss.
        for row in db.scalars(select(Forecast).where(Forecast.item_id == milk.id)):
            row.created_at = utcnow() - timedelta(days=2)
        db.commit()

    rows = db.scalar(
        select(func.count(Forecast.id)).where(Forecast.item_id == milk.id)
    )
    assert rows == 7, 'the window is replaced, not appended to'


def test_tc_fc05_an_empty_forecast_writes_nothing(db, vendor, milk):
    """A model that produced no days must not leave a phantom cache entry."""

    class _Empty:
        days = []
        model_version = 'none'
        total_predicted = 0.0

    forecast_cache.store(db, vendor_id=vendor.id, item_id=milk.id, result=_Empty())
    db.commit()

    assert db.scalar(select(func.count(Forecast.id))) == 0


def test_tc_fc06_the_cache_is_per_item(db, vendor, milk):
    """One item's forecast must never satisfy another item's read."""
    other = InventoryItem(
        vendor_id=vendor.id,
        sku_name='Atta',
        category='staples',
        current_qty=50,
        unit='kg',
        unit_cost=38,
        unit_price=46,
        reorder_point=20,
    )
    db.add(other)
    db.commit()

    forecast_cache.total_for(db, milk, horizon_days=7, history=_history(db, milk))
    db.commit()

    assert forecast_cache.read(db, item_id=milk.id, horizon_days=7) is not None
    assert forecast_cache.read(db, item_id=other.id, horizon_days=7) is None
