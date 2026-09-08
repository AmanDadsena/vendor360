"""Forecasting, safety stock, health score, voice and OCR — Test Plan 3.1-3.5."""
from __future__ import annotations

import random
from datetime import date, timedelta

import pytest

from app.services.forecasting import MIN_DAYS_FOR_MODEL, forecast_item, mape
from app.services.health_score import (
    WEIGHTS,
    compute_health_score,
    validate_weights,
)
from app.services.nlp_parser import REVIEW_THRESHOLD, parse_utterance
from app.services.ocr_parser import parse_receipt
from app.services.safety_stock import compute_reorder_point

TODAY = date(2026, 8, 29)


def history(days: int, base: float = 20.0, seed: int = 3, weekend_lift: float = 1.0):
    rng = random.Random(seed)
    rows = []
    for i in range(days, 0, -1):
        d = TODAY - timedelta(days=i)
        q = base * (weekend_lift if d.weekday() >= 5 else 1.0) * rng.uniform(0.85, 1.15)
        rows.append((d, round(q, 1)))
    return rows


# --------------------------------------------------------- 3.3 forecasting
class TestFestivalForecast:
    """TC-F01 — demand rises ahead of a festival, with the festival named."""

    def test_sweets_spike_before_ganesh_chaturthi(self):
        result = forecast_item(
            item_id="i", sku_name="Ladoo", category_key="sweets",
            history=history(90, base=10), horizon_days=10, today=date(2026, 9, 8),
        )
        drivers = {d.driver for d in result.days if d.driver}
        assert "Ganesh Chaturthi" in drivers

        peak = result.peak
        assert peak.driver_effect > 0.5
        # The spike must land on or before the festival, not after it.
        assert peak.on <= date(2026, 9, 14)

    def test_non_festival_category_is_unaffected(self):
        """A festival that lifts sweets must not silently lift soap."""
        result = forecast_item(
            item_id="i", sku_name="Soap", category_key="personal_care",
            history=history(90, base=10), horizon_days=8, today=date(2026, 9, 8),
        )
        assert all(d.driver != "Ganesh Chaturthi" for d in result.days)


class TestWeatherForecast:
    """TC-F02 — weather-linked SKUs adjust to the rain forecast."""

    def test_monsoon_goods_rise_in_wet_season(self):
        wet = forecast_item(
            item_id="i", sku_name="Umbrella", category_key="monsoon",
            history=history(90, base=4), horizon_days=7, today=date(2026, 7, 15),
        )
        dry = forecast_item(
            item_id="i", sku_name="Umbrella", category_key="monsoon",
            history=history(90, base=4), horizon_days=7, today=date(2026, 12, 15),
        )
        assert wet.total_predicted > dry.total_predicted
        assert any(d.driver == "Heavy rain forecast" for d in wet.days)

    def test_beverages_are_suppressed_by_rain(self):
        """Rain sensitivity is signed: some categories fall when it rains."""
        result = forecast_item(
            item_id="i", sku_name="Soft Drink", category_key="beverages",
            history=history(90, base=15), horizon_days=7, today=date(2026, 7, 15),
        )
        assert any(d.driver_effect < 0 for d in result.days)


class TestColdStart:
    """TC-F04 — a new item falls back to category averages, never fails."""

    def test_no_history_uses_category_mean(self):
        result = forecast_item(
            item_id="i", sku_name="New Item", category_key="dairy",
            history=[], horizon_days=5, today=TODAY, category_daily_mean=12.0,
        )
        assert result.used_fallback
        assert result.model_version == "category-fallback-v1"
        assert len(result.days) == 5
        assert result.days[0].predicted > 0

    def test_thin_history_still_falls_back(self):
        result = forecast_item(
            item_id="i", sku_name="Newish", category_key="staples",
            history=history(MIN_DAYS_FOR_MODEL), horizon_days=3, today=TODAY,
        )
        assert result.used_fallback

    def test_sufficient_history_trains_a_model(self):
        result = forecast_item(
            item_id="i", sku_name="Rice", category_key="staples",
            history=history(90), horizon_days=3, today=TODAY,
        )
        assert not result.used_fallback
        assert result.model_version.startswith("vendor360-hybrid")


class TestForecastMechanics:
    def test_learns_weekend_pattern(self):
        result = forecast_item(
            item_id="i", sku_name="Milk", category_key="household",
            history=history(90, base=40, weekend_lift=1.6),
            horizon_days=14, today=TODAY,
        )
        weekend = [d.predicted for d in result.days if d.on.weekday() >= 5]
        weekday = [d.predicted for d in result.days if d.on.weekday() < 5]
        assert sum(weekend) / len(weekend) > sum(weekday) / len(weekday) * 1.2

    def test_forecast_starts_tomorrow_not_today(self):
        """Today is in progress; forecasting it would be reporting, not predicting."""
        result = forecast_item(
            item_id="i", sku_name="Rice", category_key="staples",
            history=history(90), horizon_days=5, today=TODAY,
        )
        assert result.days[0].on == TODAY + timedelta(days=1)
        assert len(result.days) == 5

    def test_incomplete_today_does_not_drag_prediction_down(self):
        """A gap between the last sale and today must not read as zero demand."""
        rows = history(90, base=40)
        stale = [(d, q) for d, q in rows if d <= TODAY - timedelta(days=2)]

        fresh_result = forecast_item(
            item_id="i", sku_name="Milk", category_key="household",
            history=rows, horizon_days=3, today=TODAY,
        )
        stale_result = forecast_item(
            item_id="i", sku_name="Milk", category_key="household",
            history=stale, horizon_days=3, today=TODAY,
        )
        # Two missing days should not halve the forecast.
        assert stale_result.total_predicted > fresh_result.total_predicted * 0.6

    def test_mape_ignores_zero_actual_days(self):
        assert mape([0, 0], [5, 5]) is None
        assert mape([10, 0, 20], [12, 5, 18]) == pytest.approx(15.0, abs=0.1)


# -------------------------------------------------------- 3.3 safety stock
class TestSafetyStock:
    """TC-F03 — reorder points move with sales velocity, not fixed forever."""

    def test_threshold_rises_with_demand(self):
        low = compute_reorder_point(
            recent_daily_demand=[5] * 14, category_key="staples", lead_days=2
        )
        high = compute_reorder_point(
            recent_daily_demand=[25] * 14, category_key="staples", lead_days=2
        )
        assert high.reorder_point > low.reorder_point * 3

    def test_volatility_widens_the_buffer(self):
        steady = compute_reorder_point(
            recent_daily_demand=[10] * 14, category_key="staples", lead_days=2
        )
        erratic = compute_reorder_point(
            recent_daily_demand=[2, 18, 3, 17, 4, 16, 5, 15, 2, 18, 3, 17, 4, 16],
            category_key="staples", lead_days=2,
        )
        assert erratic.safety_stock > steady.safety_stock

    def test_perishable_is_capped_by_shelf_life(self):
        demand = [4, 9, 2, 11, 3, 8, 5, 10, 2, 7]
        advice = compute_reorder_point(
            recent_daily_demand=demand, category_key="dairy", lead_days=5
        )
        assert advice.capped_by_shelf_life
        assert advice.reorder_point <= advice.mean_daily_demand * 3 + 0.01
        assert "shelf life" in advice.reason

    def test_order_quantity_respects_the_shelf_life_cap(self):
        """The cap must bind the quantity, not only the trigger."""
        demand = [4, 9, 2, 11, 3, 8, 5, 10, 2, 7]
        advice = compute_reorder_point(
            recent_daily_demand=demand, category_key="dairy",
            lead_days=2, current_qty=0,
        )
        assert advice.suggested_order_qty <= advice.mean_daily_demand * 3 + 0.01

    def test_non_perishable_is_not_capped(self):
        demand = [4, 9, 2, 11, 3, 8, 5, 10, 2, 7]
        advice = compute_reorder_point(
            recent_daily_demand=demand, category_key="staples", lead_days=5
        )
        assert not advice.capped_by_shelf_life

    def test_forecast_raises_threshold_before_a_spike(self):
        base = compute_reorder_point(
            recent_daily_demand=[10] * 14, category_key="staples", lead_days=3
        )
        ahead = compute_reorder_point(
            recent_daily_demand=[10] * 14, category_key="staples", lead_days=3,
            forecast_daily=[30, 32, 35],
        )
        assert ahead.reorder_point > base.reorder_point


# ------------------------------------------------------- 3.5 health score
class TestHealthScore:
    def test_weights_must_sum_to_one(self):
        validate_weights(WEIGHTS)
        with pytest.raises(ValueError, match="must sum to 1.0"):
            validate_weights({"consistency": 0.5, "turnover": 0.5, "waste": 0.2})

    def test_established_vendor_scores_with_breakdown(self):
        """TC-H01 — full score plus the three visible components."""
        start = TODAY - timedelta(days=89)
        score = compute_health_score(
            sale_days={start + timedelta(days=i) for i in range(90)},
            window_start=start, window_end=TODAY,
            cogs=180000, avg_inventory_value=20000,
            waste_value=4000, purchase_value=150000,
        )
        assert not score.provisional
        assert score.band in {"strong", "stable"}
        assert {c.key for c in score.components} == {"consistency", "turnover", "waste"}
        assert sum(c.contribution for c in score.components) == pytest.approx(
            score.score, abs=0.05
        )

    def test_sparse_history_is_provisional(self):
        """TC-H02 — thin data must not produce a falsely precise number."""
        start = TODAY - timedelta(days=19)
        score = compute_health_score(
            sale_days={start + timedelta(days=i) for i in range(0, 20, 3)},
            window_start=start, window_end=TODAY,
            cogs=12000, avg_inventory_value=9000,
            waste_value=1800, purchase_value=14000,
        )
        assert score.provisional
        assert score.band == "provisional"
        assert "60 days" in score.explanation

    def test_bursty_trading_scores_below_steady(self):
        start = TODAY - timedelta(days=89)
        common = dict(
            window_start=start, window_end=TODAY, cogs=120000,
            avg_inventory_value=20000, waste_value=6000, purchase_value=100000,
        )
        steady = compute_health_score(
            sale_days={start + timedelta(days=i) for i in range(90)}, **common
        )
        bursty = compute_health_score(
            sale_days={start + timedelta(days=i) for i in range(0, 90, 4)}, **common
        )
        assert steady.score > bursty.score

    def test_waste_reduces_the_score(self):
        start = TODAY - timedelta(days=89)
        common = dict(
            sale_days={start + timedelta(days=i) for i in range(90)},
            window_start=start, window_end=TODAY,
            cogs=120000, avg_inventory_value=20000, purchase_value=100000,
        )
        clean = compute_health_score(waste_value=2000, **common)
        wasteful = compute_health_score(waste_value=30000, **common)
        assert clean.score > wasteful.score

    def test_turnover_discriminates_across_the_kirana_range(self):
        """A component that returns the same value for everyone carries no signal."""
        start = TODAY - timedelta(days=89)
        common = dict(
            sale_days={start + timedelta(days=i) for i in range(90)},
            window_start=start, window_end=TODAY,
            waste_value=3000, purchase_value=100000,
        )
        scores = [
            compute_health_score(cogs=cogs, avg_inventory_value=20000, **common)
            for cogs in (30000, 90000, 200000, 400000)
        ]
        turnovers = [
            next(c.value for c in s.components if c.key == "turnover") for s in scores
        ]
        assert len(set(turnovers)) == len(turnovers)
        assert turnovers == sorted(turnovers)

    def test_explanation_never_names_one_component_as_both(self):
        start = TODAY - timedelta(days=89)
        score = compute_health_score(
            sale_days={start + timedelta(days=i) for i in range(90)},
            window_start=start, window_end=TODAY,
            cogs=500000, avg_inventory_value=10000,
            waste_value=100, purchase_value=100000,
        )
        assert score.explanation.count("sales consistency") <= 1

    def test_health_score_report_generates_lending_statement(
        self, client_vendor, vendor
    ):
        res = client_vendor.get("/health-score/report")
        assert res.status_code == 200
        data = res.json()
        assert data["store_name"] == vendor.store_name
        assert data["phone"] == vendor.phone
        assert "VENDOR360 OPERATIONAL CREDIT ASSESSMENT REPORT" in data["statement"]
        assert "score" in data
        assert "band" in data
        assert data["score"] >= 0


# --------------------------------------------------------------- 3.1 voice
class TestVoiceParsing:
    def test_clear_hindi_update_parses(self):
        """TC-V01 — a clean utterance maps to the right items and quantities."""
        result = parse_utterance("20 doodh packet aur 5 kilo chawal beche")
        assert result.movement == "sale"
        assert [(l.sku_name, l.qty) for l in result.lines] == [("Milk", 20), ("Rice", 5)]
        assert not result.needs_review

    def test_devanagari_and_marathi(self):
        hindi = parse_utterance("बीस दूध पैकेट और पांच किलो चावल बेचे")
        assert [(l.sku_name, l.qty) for l in hindi.lines] == [("Milk", 20), ("Rice", 5)]

        marathi = parse_utterance("दहा किलो कांदा विकले", language="mr")
        assert marathi.lines[0].sku_name == "Onion"
        assert marathi.lines[0].qty == 10

    def test_units_attach_to_the_nearest_product(self):
        """Two products, two units — neither may steal the other's."""
        result = parse_utterance("20 doodh packet aur 5 kilo chawal beche")
        by_sku = {l.sku_name: l.unit for l in result.lines}
        assert by_sku["Milk"] == "pkt"
        assert by_sku["Rice"] == "kg"

    def test_low_asr_confidence_forces_review(self):
        """TC-V02 — a noisy transcription cannot auto-commit."""
        result = parse_utterance("20 doodh packet beche", asr_confidence=0.55)
        assert result.needs_review
        assert all(l.confidence < REVIEW_THRESHOLD for l in result.lines)

    def test_missing_quantity_is_flagged_not_guessed_silently(self):
        result = parse_utterance("doodh beche")
        assert result.lines[0].qty == 1
        assert result.lines[0].needs_review

    def test_wastage_beats_the_sale_verb(self):
        """'kharab ho gaya' contains a sale word; reading it as a sale hides spoilage."""
        result = parse_utterance("10 kilo tamatar kharab ho gaya")
        assert result.movement == "wastage"

    def test_restock_is_detected(self):
        assert parse_utterance("50 doodh packet aaya").movement == "restock"

    def test_unknown_catalogue_scoping(self):
        """A store that does not sell umbrellas cannot have one misheard into stock."""
        result = parse_utterance("2 chhata beche", known_skus=["Milk", "Rice"])
        assert result.lines == []

    def test_quick_action_phrases_parse_cleanly(self):
        # Restock
        r1 = parse_utterance("20 doodh packet aaya")
        assert r1.movement == "restock"
        assert r1.lines[0].sku_name == "Milk"
        assert r1.lines[0].qty == 20

        # Sale
        r2 = parse_utterance("5 kilo chawal becha")
        assert r2.movement == "sale"
        assert r2.lines[0].sku_name == "Rice"
        assert r2.lines[0].qty == 5

        # Wastage
        r3 = parse_utterance("2 packet bread kharab")
        assert r3.movement == "wastage"
        assert r3.lines[0].sku_name == "Bread"
        assert r3.lines[0].qty == 2

        # English
        r4 = parse_utterance("sold 12 eggs")
        assert r4.movement == "sale"
        assert r4.lines[0].sku_name == "Eggs"
        assert r4.lines[0].qty == 12


# ----------------------------------------------------------------- 3.2 ocr
RECEIPT = """SHREE BALAJI TRADERS
GST NO: 27AABCT1234M1Z5
Item              Qty   Rate   Amount
Amul Milk 500ml    20   24.00   480.00
Tata Salt 1kg       5   22.00   110.00
Parle Biscuits     12   10.00   120.00
TOTAL                           710.00"""


class TestOcrParsing:
    def test_clean_receipt_extracts_all_lines(self):
        """TC-O01 — every line item, quantity and total read correctly."""
        result = parse_receipt(RECEIPT, captured_on=TODAY)
        assert result.supplier == "SHREE BALAJI TRADERS"
        assert [l.sku_name for l in result.lines] == ["Milk", "Salt", "Biscuits"]
        assert result.total_matches
        assert result.computed_total == 710.0

    def test_expiry_is_computed_per_category(self):
        """TC-O04 — shelf life comes from the category, not the receipt."""
        result = parse_receipt(RECEIPT, captured_on=TODAY)
        by_sku = {l.sku_name: l for l in result.lines}
        assert by_sku["Milk"].expires_on == TODAY + timedelta(days=3)
        assert by_sku["Biscuits"].expires_on == TODAY + timedelta(days=120)
        assert by_sku["Salt"].expires_on is None  # non-perishable

    def test_blurry_capture_flags_rather_than_blocks(self):
        """TC-O02 — low confidence highlights rows, it does not reject the receipt."""
        result = parse_receipt(RECEIPT, captured_on=TODAY, ocr_confidence=0.5)
        assert result.needs_review
        assert result.review_count == len(result.lines)
        assert len(result.lines) == 3  # still parsed

    def test_unreadable_product_is_flagged_not_invented(self):
        """TC-O03 — an unrecognised line must not be silently coerced to a SKU."""
        result = parse_receipt(
            RECEIPT.replace("Parle Biscuits", "Xyzq Unknwn"), captured_on=TODAY
        )
        unknown = [l for l in result.lines if l.sku_name is None]
        assert len(unknown) == 1
        assert unknown[0].needs_review
        assert "product not recognised" in unknown[0].issues

    def test_arithmetic_mismatch_is_caught(self):
        bad = RECEIPT.replace("20   24.00   480.00", "20   24.00   999.00")
        result = parse_receipt(bad, captured_on=TODAY)
        milk = next(l for l in result.lines if l.sku_name == "Milk")
        assert "qty x rate does not match amount" in milk.issues

    def test_dropped_line_is_caught_by_the_total(self):
        """Per-row confidence cannot detect a line OCR never saw; the total can."""
        missing = RECEIPT.replace("Tata Salt 1kg       5   22.00   110.00\n", "")
        result = parse_receipt(missing, captured_on=TODAY)
        assert not result.total_matches
        assert result.needs_review

    def test_pack_size_is_not_read_as_quantity(self):
        result = parse_receipt(RECEIPT, captured_on=TODAY)
        milk = next(l for l in result.lines if l.sku_name == "Milk")
        assert milk.qty == 20  # not 500 from "500ml"
        assert milk.unit == "ml"
