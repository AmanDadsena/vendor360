"""Context-aware demand forecasting (PRD 5.1, TC-F01..F04).

A hybrid, and deliberately so. A gradient-boosted regressor learns what 90 days
of history can actually teach -- weekday rhythm, recent level, short trend --
while festival and weather effects are applied as explicit multipliers from
`signals`.

The reason is a data limitation, not a modelling preference: Diwali occurs once
a year, so a model fitted on a single season has never seen one and cannot
learn its effect at any amount of tuning. Learning the learnable part and
declaring the rest also makes every prediction attributable, which is what lets
the app say "+34%, Ganesh Chaturthi in 3 days" instead of showing a number the
vendor has no reason to trust (UI/UX 5.5).

The TRD names Prophet. Prophet compiles a Stan backend and is fragile to
install on current Python; this module keeps the same feature semantics
(seasonality plus holiday regressors) behind a stable interface, so swapping it
in later means changing `_fit_base_model` and nothing that calls it.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, timedelta

import numpy as np
from sklearn.ensemble import GradientBoostingRegressor

from .catalog import category
from .signals import festival_intensity, forecast_weather, weather_effect

MODEL_VERSION = "vendor360-hybrid-gbr-v1"

# Below this many observed days the learned component is noise. The category
# fallback takes over instead of reporting false precision (TC-F04).
MIN_DAYS_FOR_MODEL = 21


@dataclass
class DayPrediction:
    on: date
    predicted: float
    lower: float
    upper: float
    driver: str | None
    driver_effect: float
    baseline: float
    features: dict = field(default_factory=dict)


@dataclass
class ForecastResult:
    item_id: str
    sku_name: str
    category: str
    days: list[DayPrediction]
    model_version: str
    used_fallback: bool
    history_days: int

    @property
    def total_predicted(self) -> float:
        return sum(d.predicted for d in self.days)

    @property
    def peak(self) -> DayPrediction | None:
        return max(self.days, key=lambda d: d.predicted) if self.days else None


def daily_series(
    rows: list[tuple[date, float]], start: date, end: date
) -> tuple[list[date], np.ndarray]:
    """Collapse transactions into a dense daily series.

    Days with no sale become 0 rather than being skipped. A gap is information
    -- it means nothing sold -- and dropping it would bias the mean upward and
    systematically over-order.
    """
    totals: dict[date, float] = defaultdict(float)
    for day, qty in rows:
        totals[day] += qty

    days: list[date] = []
    values: list[float] = []
    cursor = start
    while cursor <= end:
        days.append(cursor)
        values.append(totals.get(cursor, 0.0))
        cursor += timedelta(days=1)

    return days, np.asarray(values, dtype=float)


def _design_row(values: np.ndarray, idx: int, day: date) -> list[float]:
    """Features for position `idx`, using only data strictly before it.

    Every lag and window looks backward only. A feature built from the target
    day would leak the answer into training and produce an accuracy figure the
    model cannot reproduce in use.
    """
    lag1 = values[idx - 1]
    lag7 = values[idx - 7] if idx >= 7 else values[:idx].mean()
    lag14 = values[idx - 14] if idx >= 14 else values[:idx].mean()
    roll7 = values[max(0, idx - 7):idx].mean()
    roll28 = values[max(0, idx - 28):idx].mean()
    trend = roll7 - roll28

    dow = day.weekday()
    return [
        lag1, lag7, lag14, roll7, roll28, trend,
        float(dow),
        1.0 if dow >= 5 else 0.0,
        float(day.day),  # intra-month rhythm: salary-week restocking
    ]


def _fit_base_model(
    days: list[date], values: np.ndarray
) -> tuple[GradientBoostingRegressor | None, float]:
    """Fit the learned component. Returns (model, residual_std)."""
    start = 14  # need history for the longest lag
    if len(values) - start < MIN_DAYS_FOR_MODEL:
        return None, 0.0

    X = [_design_row(values, i, days[i]) for i in range(start, len(values))]
    y = values[start:]

    model = GradientBoostingRegressor(
        n_estimators=180,
        learning_rate=0.06,
        max_depth=3,
        subsample=0.9,
        random_state=42,  # reproducible: the same history yields the same forecast
    )
    model.fit(np.asarray(X), y)

    residuals = y - model.predict(np.asarray(X))
    return model, float(np.std(residuals))


def forecast_item(
    *,
    item_id: str,
    sku_name: str,
    category_key: str,
    history: list[tuple[date, float]],
    horizon_days: int = 7,
    today: date | None = None,
    lat: float = 18.52,
    lon: float = 73.86,
    category_daily_mean: float | None = None,
) -> ForecastResult:
    """Predict demand for the next `horizon_days`.

    `category_daily_mean` is the cold-start escape hatch: a SKU added this
    morning has no history of its own, so it borrows its category's average
    rather than returning nothing (TC-F04).
    """
    today = today or date.today()

    observed = [(d, q) for d, q in history if d <= today]
    used_fallback = False

    if observed:
        start = min(d for d, _ in observed)
        # Ends at the last day that actually has data, not at `today`.
        # Internal gaps are still padded with zeros -- a day with no sales
        # genuinely means nothing sold. The trailing edge is different: a
        # forecast run at 9am, before the day's sales are logged, would read
        # today as a zero-sales day and bias every prediction downward. Absence
        # of data is not evidence of absence of demand.
        last_observed = max(d for d, _ in observed)
        days, values = daily_series(observed, start, last_observed)
    else:
        last_observed = today
        days, values = [], np.asarray([], dtype=float)

    history_days = len(values)
    model, resid_std = _fit_base_model(days, values) if history_days else (None, 0.0)

    if model is None:
        used_fallback = True
        if history_days:
            base_level = float(values[-14:].mean()) if history_days >= 3 else float(values.mean())
        else:
            base_level = float(category_daily_mean or 0.0)
        # Wide band, because a category average is a weak claim about one SKU.
        resid_std = max(base_level * 0.45, 0.6)
    else:
        base_level = float(values[-7:].mean())

    cat = category(category_key)
    working = list(values)
    predictions: list[DayPrediction] = []

    # Walk forward from the last observed day rather than from today, so the
    # lag chain stays continuous across the gap where today's sales are not in
    # yet. Those catch-up days are predicted but not returned -- the vendor is
    # asking what to stock next, not what already happened.
    catch_up = max(0, (today - last_observed).days)

    for step in range(1, catch_up + horizon_days + 1):
        target = last_observed + timedelta(days=step)

        if model is not None:
            arr = np.asarray(working, dtype=float)
            row = _design_row(arr, len(arr), target)
            learned = float(model.predict(np.asarray([row]))[0])
        else:
            learned = base_level
            row = []

        learned = max(0.0, learned)

        # Exogenous effects, applied on top and kept separable so each one can
        # be named in the UI.
        fest_effect, fest_driver = festival_intensity(target, category_key)
        wx = forecast_weather(target, lat, lon)
        wx_effect, wx_driver = weather_effect(wx, category_key)

        fest_effect *= cat.festival_sensitivity
        predicted = max(0.0, learned * (1.0 + fest_effect + wx_effect))

        # The driver is whichever exogenous signal moved the number most; if
        # neither did, the honest answer is that this is just the usual rhythm.
        if abs(fest_effect) >= abs(wx_effect) and abs(fest_effect) >= 0.05:
            driver, driver_effect = fest_driver, fest_effect
        elif abs(wx_effect) >= 0.05:
            driver, driver_effect = wx_driver, wx_effect
        else:
            driver, driver_effect = None, 0.0

        # Feed every step back so multi-day horizons stay self-consistent,
        # including the catch-up days that are not reported.
        working.append(predicted)

        if target <= today:
            continue

        band = max(resid_std, predicted * 0.12)
        predictions.append(
            DayPrediction(
                on=target,
                predicted=round(predicted, 2),
                lower=round(max(0.0, predicted - band), 2),
                upper=round(predicted + band, 2),
                driver=driver,
                driver_effect=round(driver_effect, 3),
                baseline=round(learned, 2),
                features={
                    "lag1": round(row[0], 2) if row else None,
                    "roll7": round(row[3], 2) if row else None,
                    "dow": target.weekday(),
                    "festival_effect": round(fest_effect, 3),
                    "festival": fest_driver,
                    "rain_mm": wx.rain_mm,
                    "temp_c": wx.temp_c,
                    "weather_effect": round(wx_effect, 3),
                    "fallback": used_fallback,
                },
            )
        )

    return ForecastResult(
        item_id=item_id,
        sku_name=sku_name,
        category=category_key,
        days=predictions,
        model_version="category-fallback-v1" if used_fallback else MODEL_VERSION,
        used_fallback=used_fallback,
        history_days=history_days,
    )


def mape(actual: list[float], predicted: list[float]) -> float | None:
    """Mean absolute percentage error, the Report 5.5 evaluation metric.

    Days with zero actual demand are excluded rather than counted: MAPE divides
    by the actual, so a zero-sale day is either a division by zero or, if
    nudged, an unbounded error that swamps every real observation.
    """
    pairs = [(a, p) for a, p in zip(actual, predicted) if a > 0]
    if not pairs:
        return None
    return round(float(np.mean([abs(a - p) / a for a, p in pairs]) * 100), 2)
