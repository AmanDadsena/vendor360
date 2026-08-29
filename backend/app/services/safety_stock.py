"""Dynamic safety stock and reorder points (PRD 5.1, TC-F03).

Replaces the fixed thresholds that ledger apps use. The classical formula is

    safety stock = Z * sigma_demand * sqrt(lead time)
    reorder point = (mean daily demand * lead time) + safety stock

which this follows, with one departure that matters for a kirana store:
perishability caps the result. A vendor selling 4 litres of milk a day with a
3-day shelf life must not be told to hold 20 litres because demand was volatile
last week -- that converts a stockout risk into guaranteed spoilage. The cap is
applied last, and the reason is reported, so the recommendation is explainable
rather than mysteriously low.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from .catalog import category

# Z-scores for the service levels declared per category in `catalog`.
# Interpolating a normal quantile for arbitrary values would add a scipy
# dependency for a table with five useful rows.
_Z_TABLE: list[tuple[float, float]] = [
    (0.80, 0.84),
    (0.85, 1.04),
    (0.88, 1.18),
    (0.90, 1.28),
    (0.93, 1.48),
    (0.95, 1.65),
    (0.97, 1.88),
    (0.99, 2.33),
]


def z_for(service_level: float) -> float:
    """Nearest tabulated Z-score for a target service level."""
    return min(_Z_TABLE, key=lambda pair: abs(pair[0] - service_level))[1]


@dataclass
class StockAdvice:
    reorder_point: float
    safety_stock: float
    mean_daily_demand: float
    demand_std: float
    lead_days: int
    service_level: float
    days_of_cover: float | None
    capped_by_shelf_life: bool
    reason: str
    suggested_order_qty: float


def compute_reorder_point(
    *,
    recent_daily_demand: list[float],
    category_key: str,
    lead_days: int,
    current_qty: float = 0.0,
    forecast_daily: list[float] | None = None,
) -> StockAdvice:
    """Reorder point for one SKU.

    `forecast_daily` is blended in when available, so a festival two days out
    raises the threshold *before* the spike rather than after the sales that
    prove it happened. That forward-looking blend is the difference between
    this and a reorder point recomputed from history alone.
    """
    cat = category(category_key)
    history = [max(0.0, q) for q in recent_daily_demand]

    if history:
        hist_mean = float(np.mean(history))
        # ddof=1: this is a sample of demand, not the population. With ~14
        # points the difference is a few percent of the buffer.
        demand_std = float(np.std(history, ddof=1)) if len(history) > 1 else hist_mean * 0.3
    else:
        hist_mean, demand_std = 0.0, 0.0

    if forecast_daily:
        fc_mean = float(np.mean(forecast_daily[:lead_days] or forecast_daily))
        # Weighted toward the forecast, which already contains the history's
        # signal plus the festival and weather context history cannot supply.
        mean_daily = 0.35 * hist_mean + 0.65 * fc_mean
    else:
        mean_daily = hist_mean

    z = z_for(cat.service_level)
    safety = z * demand_std * math.sqrt(max(1, lead_days))
    reorder = (mean_daily * lead_days) + safety

    capped = False
    reason = f"{lead_days}-day lead time at {cat.service_level:.0%} service level"

    if cat.shelf_life_days is not None and mean_daily > 0:
        # Never hold more than can be sold before it spoils. One shelf life of
        # demand is the ceiling; beyond it, every extra unit is waste.
        ceiling = mean_daily * cat.shelf_life_days
        if reorder > ceiling:
            reorder, safety = ceiling, max(0.0, ceiling - mean_daily * lead_days)
            capped = True
            reason = (
                f"capped at {cat.shelf_life_days}-day shelf life "
                f"({cat.label_en.lower()} spoils before extra stock sells)"
            )

    days_of_cover = round(current_qty / mean_daily, 1) if mean_daily > 0 else None

    # Order up to the reorder point plus one lead time of demand, so the next
    # delivery arrives before the buffer is consumed.
    target = reorder + (mean_daily * lead_days)

    # The shelf-life ceiling has to bind here too, not only on the trigger
    # above. The reorder point decides *when* to order; the target decides
    # *how much*. Capping only the trigger would refuse to hold more than three
    # days of milk and then order four and a half days of it -- the constraint
    # leaks through the quantity it was meant to govern.
    if cat.shelf_life_days is not None and mean_daily > 0:
        target = min(target, mean_daily * cat.shelf_life_days)

    suggested = max(0.0, target - current_qty) if current_qty <= reorder else 0.0

    return StockAdvice(
        reorder_point=round(reorder, 2),
        safety_stock=round(safety, 2),
        mean_daily_demand=round(mean_daily, 2),
        demand_std=round(demand_std, 2),
        lead_days=lead_days,
        service_level=cat.service_level,
        days_of_cover=days_of_cover,
        capped_by_shelf_life=capped,
        reason=reason,
        suggested_order_qty=round(suggested, 2),
    )
