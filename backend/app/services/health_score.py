"""Micro-credit Health Score (PRD 5.2, TC-H01..H03).

Turns ordinary use of the app into the operating record a lender cannot
otherwise see. Three behaviours are measured, each normalised to 0-100 and
reported alongside the composite, because the UI/UX guide requires the
breakdown to be visible at all times -- a vendor must never be shown an opaque
number that decides their access to credit.

Scoring is deliberately transparent and rule-based rather than a fitted model.
With no repayment outcomes to train against, a learned model would encode the
authors' guesses behind a veneer of objectivity; stated weights can at least be
argued with, audited, and revised when pilot repayment data arrives.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta

import numpy as np

# A score below this many days of history is reported as provisional. Two
# months is roughly the point at which a weekly rhythm is distinguishable from
# noise; below it the number would be precision the data cannot support
# (TC-H02).
MIN_DAYS_FOR_FULL_SCORE = 60


# ---------------------------------------------------------------------------
# Weighting
#
# How much each behaviour counts toward the composite. These three must sum to
# 1.0; `validate_weights()` enforces it at import time.
#
# This is a policy judgment, not a technical default. Each choice advantages a
# different kind of vendor:
#
#   consistency  rewards showing up daily -- disciplined record-keeping and a
#                predictable business. Favours the careful small vendor. But a
#                vendor can be consistent while barely trading.
#
#   turnover     rewards moving stock -- cash actually cycling through the
#                business, which is what repayment comes out of. Closest proxy
#                for capacity to repay. But it favours higher-volume stores and
#                may penalise a small vendor who is nonetheless reliable.
#
#   waste        rewards not spoiling stock -- operational skill and care.
#                Aligns with the SDG 12 framing in the report. But it is the
#                weakest signal of repayment, and punishes perishable-heavy
#                stores for their category mix rather than their competence.
# ---------------------------------------------------------------------------
WEIGHTS: dict[str, float] = {
    "consistency": 0.40,
    "turnover": 0.40,
    "waste": 0.20,
}


def validate_weights(weights: dict[str, float]) -> None:
    """Fail loudly at import if the weights stop summing to 1.

    A silent drift here would rescale every vendor's score without any error,
    and the change would only surface as unexplained score movement.
    """
    total = sum(weights.values())
    if abs(total - 1.0) > 1e-9:
        raise ValueError(
            f"Health Score weights must sum to 1.0, got {total:.4f}: {weights}"
        )
    missing = {"consistency", "turnover", "waste"} - set(weights)
    if missing:
        raise ValueError(f"Health Score weights missing components: {missing}")


validate_weights(WEIGHTS)


@dataclass
class ScoreComponent:
    key: str
    label: str
    value: float          # 0-100
    weight: float
    contribution: float   # value * weight
    detail: str


@dataclass
class HealthScore:
    score: float
    band: str
    provisional: bool
    days_of_history: int
    components: list[ScoreComponent]
    explanation: str

    @property
    def as_dict(self) -> dict:
        return {
            "score": self.score,
            "band": self.band,
            "provisional": self.provisional,
            "days_of_history": self.days_of_history,
            "explanation": self.explanation,
            "components": [
                {
                    "key": c.key,
                    "label": c.label,
                    "value": c.value,
                    "weight": c.weight,
                    "contribution": round(c.contribution, 2),
                    "detail": c.detail,
                }
                for c in self.components
            ],
        }


def _band(score: float, provisional: bool) -> str:
    if provisional:
        return "provisional"
    if score >= 75:
        return "strong"
    if score >= 55:
        return "stable"
    if score >= 35:
        return "building"
    return "at_risk"


def _consistency_score(
    sale_days: set[date], window_start: date, window_end: date
) -> tuple[float, str]:
    """Regularity of trading activity.

    Combines coverage (what share of days saw a sale) with steadiness (whether
    activity is evenly spread or clustered in bursts). A vendor who logs every
    day for a week and then vanishes for three should not score as well as one
    who trades steadily, even at identical coverage.
    """
    total_days = (window_end - window_start).days + 1
    if total_days <= 0:
        return 0.0, "no trading window"

    coverage = len(sale_days) / total_days

    if len(sale_days) < 2:
        return round(coverage * 100 * 0.5, 1), f"{len(sale_days)} active day(s)"

    ordered = sorted(sale_days)
    gaps = np.array([(b - a).days for a, b in zip(ordered, ordered[1:])], dtype=float)

    # Coefficient of variation of the gaps between active days. Even spacing
    # gives cv near 0; bursty activity pushes it up.
    mean_gap = float(gaps.mean())
    cv = float(gaps.std() / mean_gap) if mean_gap > 0 else 1.0
    steadiness = max(0.0, 1.0 - min(cv, 1.0))

    value = (0.7 * coverage + 0.3 * steadiness) * 100
    return (
        round(min(100.0, value), 1),
        f"active {len(sale_days)}/{total_days} days, avg gap {mean_gap:.1f}d",
    )


def _turnover_score(
    cogs: float, avg_inventory_value: float, days: int
) -> tuple[float, str]:
    """Inventory turns, annualised.

    Turns = cost of goods sold / average inventory held.

    Calibrated to kirana reality, not to general retail. A kirana store holds
    very little stock and restocks constantly, so it turns inventory far faster
    than a supermarket: 20-30 turns a year is ordinary and 40+ is common on a
    fast-moving FMCG basket. An earlier 15-turn benchmark scored every real
    vendor at 100, which made a 40%-weighted component carry no information at
    all.

    The curve below is piecewise so it discriminates across the range vendors
    actually occupy, and still saturates -- past roughly 60 turns the store is
    usually running dangerously thin rather than performing well, and should
    not out-score a healthy one.
    """
    if avg_inventory_value <= 0 or days <= 0:
        return 0.0, "no inventory value recorded"

    period_turns = cogs / avg_inventory_value
    annual_turns = period_turns * (365.0 / days)

    # Anchors: 12 turns is weak for kirana, 25 is solid, 40 is excellent.
    if annual_turns <= 12:
        value = (annual_turns / 12.0) * 45.0
    elif annual_turns <= 25:
        value = 45.0 + ((annual_turns - 12.0) / 13.0) * 30.0
    elif annual_turns <= 40:
        value = 75.0 + ((annual_turns - 25.0) / 15.0) * 20.0
    else:
        # Diminishing returns, and never a perfect score from volume alone.
        value = min(100.0, 95.0 + (annual_turns - 40.0) * 0.25)

    return round(min(100.0, value), 1), f"{annual_turns:.1f} inventory turns/year"


def _waste_score(waste_value: float, purchase_value: float) -> tuple[float, str]:
    """Spoilage as a share of purchases, inverted.

    5% waste is treated as the acceptable norm for a mixed kirana basket and
    scores 100; 25% or worse scores 0. Linear between them.
    """
    if purchase_value <= 0:
        return 50.0, "no purchases recorded"

    ratio = waste_value / purchase_value
    if ratio <= 0.05:
        value = 100.0
    elif ratio >= 0.25:
        value = 0.0
    else:
        value = (1.0 - (ratio - 0.05) / 0.20) * 100.0

    return round(value, 1), f"{ratio:.1%} of purchase value wasted"


def compute_health_score(
    *,
    sale_days: set[date],
    window_start: date,
    window_end: date,
    cogs: float,
    avg_inventory_value: float,
    waste_value: float,
    purchase_value: float,
    weights: dict[str, float] | None = None,
) -> HealthScore:
    """Composite score with its full breakdown.

    Returns a `provisional` result rather than refusing when history is thin:
    the PRD targets a computed score for 100% of active vendors, and a vendor
    with three weeks of data still deserves to see where they stand -- clearly
    labelled as not yet firm (TC-H02).
    """
    weights = weights or WEIGHTS
    validate_weights(weights)

    days = (window_end - window_start).days + 1
    provisional = days < MIN_DAYS_FOR_FULL_SCORE or len(sale_days) < 15

    consistency, c_detail = _consistency_score(sale_days, window_start, window_end)
    turnover, t_detail = _turnover_score(cogs, avg_inventory_value, days)
    waste, w_detail = _waste_score(waste_value, purchase_value)

    raw = {"consistency": consistency, "turnover": turnover, "waste": waste}
    labels = {
        "consistency": "Sales consistency",
        "turnover": "Inventory turnover",
        "waste": "Waste control",
    }
    details = {"consistency": c_detail, "turnover": t_detail, "waste": w_detail}

    components = [
        ScoreComponent(
            key=key,
            label=labels[key],
            value=raw[key],
            weight=weights[key],
            contribution=raw[key] * weights[key],
            detail=details[key],
        )
        for key in ("consistency", "turnover", "waste")
    ]

    score = round(sum(c.contribution for c in components), 1)
    band = _band(score, provisional)

    strongest = max(components, key=lambda c: c.value)
    weakest = min(components, key=lambda c: c.value)

    if provisional:
        explanation = (
            f"Provisional score from {days} days of history. "
            f"{MIN_DAYS_FOR_FULL_SCORE} days are needed for a firm score."
        )
    elif strongest.key == weakest.key or weakest.value >= 95:
        # Every component is at or near the ceiling, so naming a "weakest" is
        # both meaningless and, when it names the same component twice, reads
        # as a broken screen.
        explanation = "All three factors are strong. Keep logging daily to hold this score."
    else:
        explanation = (
            f"Strongest: {strongest.label.lower()} ({strongest.value:.0f}/100). "
            f"Most room to improve: {weakest.label.lower()} ({weakest.value:.0f}/100)."
        )

    return HealthScore(
        score=score,
        band=band,
        provisional=provisional,
        days_of_history=days,
        components=components,
        explanation=explanation,
    )
