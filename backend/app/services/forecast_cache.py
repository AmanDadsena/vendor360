"""Persisted forecasts, so reading a prediction does not refit a model.

The `Forecast` table has existed since the first commit — `horizon_date`,
`predicted_demand`, bounds, `driver`, `model_version` — and nothing ever wrote
to it. Every read refitted a gradient-boosted regressor from scratch.

For one shop looking at one item that is fine, and imperceptible. For a
wholesaler's demand outlook it is not: that screen fits a model per
(shop x SKU), so a book of twelve shops across ten catalogue lines is ~120
fits on every page load. Measured at 10.4 seconds against a seeded world,
while every other endpoint in the product answers in under sixty
milliseconds.

Forecasts are recomputed once a day because their inputs change once a day —
a day's sales are only complete when the day is. So the cache key is the date,
and staleness is simply "computed before today".
"""
from __future__ import annotations

import uuid
from datetime import date, datetime, time, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from ..models import Forecast, InventoryItem
from .forecasting import ForecastResult, forecast_item


def _start_of_today() -> datetime:
    """Midnight UTC. Anything written before it is a previous day's model."""
    return datetime.combine(datetime.now(timezone.utc).date(), time.min, timezone.utc)


def read(
    db: Session,
    *,
    item_id: uuid.UUID,
    horizon_days: int,
    today: date | None = None,
) -> list[Forecast] | None:
    """Today's stored forecast for an item, or None if absent or stale.

    Returns None rather than a partial answer when the stored horizon is
    shorter than the one asked for — half a week's demand reported as a week's
    is worse than a slow correct answer.
    """
    today = today or datetime.now(timezone.utc).date()

    # The horizon is tomorrow through today+N, not today through today+N-1.
    # `forecast_item` deliberately skips today: the day is not over, so its
    # sales are a partial observation rather than a prediction. Reading the
    # window one day earlier overlaps only N-1 of the N stored rows, which
    # fails the completeness check below on every call — a cache that writes
    # faithfully and never once reads back, with no error to show for it.
    first = today + timedelta(days=1)
    last = today + timedelta(days=horizon_days)

    rows = db.scalars(
        select(Forecast)
        .where(
            Forecast.item_id == item_id,
            Forecast.horizon_date >= first,
            Forecast.horizon_date <= last,
            Forecast.created_at >= _start_of_today(),
        )
        .order_by(Forecast.horizon_date)
    ).all()

    if len(rows) < horizon_days:
        return None
    return list(rows)


def store(
    db: Session,
    *,
    vendor_id: uuid.UUID,
    item_id: uuid.UUID,
    result: ForecastResult,
) -> None:
    """Write a forecast through, replacing any earlier one for the same days.

    Delete-then-insert rather than upsert: the table has no unique constraint
    on (item, date), and inventing one now would need a migration against a
    schema the TRD already fixed. Replacing the window is equivalent and stays
    portable across SQLite and Postgres.
    """
    if not result.days:
        return

    db.execute(
        delete(Forecast).where(
            Forecast.item_id == item_id,
            Forecast.horizon_date >= result.days[0].on,
            Forecast.horizon_date <= result.days[-1].on,
        )
    )

    for day in result.days:
        db.add(
            Forecast(
                vendor_id=vendor_id,
                item_id=item_id,
                horizon_date=day.on,
                predicted_demand=day.predicted,
                lower_bound=day.lower,
                upper_bound=day.upper,
                model_version=result.model_version,
                features_used=day.features,
                driver=day.driver,
                driver_effect=day.driver_effect,
            )
        )

    db.flush()


def total_for(
    db: Session,
    item: InventoryItem,
    *,
    horizon_days: int,
    today: date | None = None,
    history: list[tuple[date, float]] | None = None,
) -> float:
    """Expected demand over the horizon, from cache when it can be.

    The one entry point callers should use. On a hit this is a single indexed
    query; on a miss it fits the model once and writes the result through, so
    the next reader — and every other shop's outlook that includes this item —
    pays nothing.
    """
    cached = read(db, item_id=item.id, horizon_days=horizon_days, today=today)
    if cached is not None:
        return sum(row.predicted_demand for row in cached)

    result = forecast_item(
        item_id=str(item.id),
        sku_name=item.sku_name,
        category_key=item.category,
        history=history if history is not None else [],
        horizon_days=horizon_days,
        today=today,
    )
    store(db, vendor_id=item.vendor_id, item_id=item.id, result=result)
    return result.total_predicted


def warm(
    db: Session,
    items: list[InventoryItem],
    *,
    horizon_days: int,
    history_for,
    today: date | None = None,
) -> int:
    """Precompute forecasts for a set of items. Used by the seed.

    `history_for` is a callable taking an item and returning its sales history,
    so this module does not have to know how callers query transactions.
    Returns how many items were computed.
    """
    computed = 0
    for item in items:
        if read(db, item_id=item.id, horizon_days=horizon_days, today=today):
            continue
        result = forecast_item(
            item_id=str(item.id),
            sku_name=item.sku_name,
            category_key=item.category,
            history=history_for(item),
            horizon_days=horizon_days,
            today=today,
        )
        store(db, vendor_id=item.vendor_id, item_id=item.id, result=result)
        computed += 1
    return computed
