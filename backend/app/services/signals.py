"""External demand signals: regional festivals and local weather.

PRD 7 names patchy API coverage in smaller towns as a risk and prescribes "a
regional festival calendar maintained as a fallback dataset alongside the live
API". That fallback is implemented here as the primary source, behind an
interface a live provider can be dropped into, so the forecast never degrades
because a third party is unreachable.

Dates for lunar-calendar festivals are the observed Maharashtra dates and are
approximate by a day either way; the forecast uses a multi-day window around
each, so a one-day drift does not change the recommendation.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date, timedelta


@dataclass(frozen=True)
class Festival:
    name: str
    name_hi: str
    on: date

    # Days before the festival when buying actually happens. Stocking for
    # Diwali starts a week out; a one-day flag would fire far too late to be
    # actionable, which is the entire point of forecasting.
    lead_days: int

    # Categories whose demand lifts, and by how much at the peak.
    lifts: dict[str, float]


_F = Festival

FESTIVALS: list[Festival] = [
    _F("Janmashtami", "जन्माष्टमी", date(2026, 9, 4), 3,
       {"dairy": 0.70, "sweets": 0.90, "produce": 0.20}),
    _F("Ganesh Chaturthi", "गणेश चतुर्थी", date(2026, 9, 14), 7,
       {"sweets": 1.30, "dairy": 0.85, "produce": 0.55, "staples": 0.35, "household": 0.30}),
    _F("Anant Chaturdashi", "अनंत चतुर्दशी", date(2026, 9, 24), 2,
       {"sweets": 0.55, "produce": 0.30, "dairy": 0.25}),
    _F("Navratri", "नवरात्रि", date(2026, 10, 11), 4,
       {"produce": 0.60, "dairy": 0.45, "staples": 0.40, "snacks": 0.25}),
    _F("Dussehra", "दशहरा", date(2026, 10, 20), 3,
       {"sweets": 0.70, "snacks": 0.40, "dairy": 0.30}),
    _F("Karva Chauth", "करवा चौथ", date(2026, 10, 29), 2,
       {"sweets": 0.50, "dairy": 0.35, "personal_care": 0.30}),
    _F("Dhanteras", "धनतेरस", date(2026, 11, 6), 3,
       {"household": 0.80, "sweets": 0.60, "snacks": 0.35}),
    _F("Diwali", "दिवाली", date(2026, 11, 8), 8,
       {"sweets": 1.50, "snacks": 1.10, "dairy": 0.70, "household": 0.65,
        "staples": 0.45, "beverages": 0.40, "personal_care": 0.35}),
    _F("Bhai Dooj", "भाई दूज", date(2026, 11, 11), 2,
       {"sweets": 0.65, "dairy": 0.30}),
    _F("Christmas", "क्रिसमस", date(2026, 12, 25), 5,
       {"bakery": 0.90, "sweets": 0.60, "beverages": 0.40}),
    _F("Makar Sankranti", "मकर संक्रांति", date(2027, 1, 14), 4,
       {"sweets": 0.85, "staples": 0.35, "produce": 0.25}),
    _F("Holi", "होली", date(2027, 3, 22), 5,
       {"sweets": 1.00, "snacks": 0.70, "beverages": 0.60, "dairy": 0.50}),
]


def upcoming_festivals(from_date: date, within_days: int = 30) -> list[Festival]:
    horizon = from_date + timedelta(days=within_days)
    return sorted(
        (f for f in FESTIVALS if from_date <= f.on <= horizon), key=lambda f: f.on
    )


def festival_intensity(day: date, category_key: str) -> tuple[float, str | None]:
    """Demand multiplier contributed by festivals on `day`, and the driver name.

    Ramps linearly across the lead window and stops the day after the festival,
    because a vendor stocking sweets the morning after Diwali is stocking waste.
    Overlapping festivals take the strongest signal rather than summing, which
    would compound two nearby festivals into an implausible spike.
    """
    best = 0.0
    driver: str | None = None

    for fest in FESTIVALS:
        lift = fest.lifts.get(category_key)
        if lift is None:
            continue

        days_until = (fest.on - day).days
        if days_until > fest.lead_days or days_until < -1:
            continue

        if days_until >= 0:
            # Ramp toward the peak; nearest day carries the full lift.
            ramp = 1.0 - (days_until / (fest.lead_days + 1))
        else:
            ramp = 0.35  # day-after tail

        effect = lift * ramp
        if effect > best:
            best, driver = effect, fest.name

    return best, driver


@dataclass(frozen=True)
class Weather:
    on: date
    temp_c: float
    rain_mm: float
    rain_prob: float

    @property
    def is_wet(self) -> bool:
        return self.rain_mm >= 5.0


def forecast_weather(day: date, lat: float = 18.52, lon: float = 73.86) -> Weather:
    """Deterministic weather for a date and location.

    Phase I ships without a paid weather key, so this models Pune's actual
    seasonal shape: a June-September monsoon, a dry winter, and a hot April-May.
    Deterministic on (day, lat, lon) so a forecast is reproducible and testable
    -- a live provider would make the same call site non-deterministic and the
    forecast tests flaky. Swap `WeatherProvider` to go live.
    """
    doy = day.timetuple().tm_yday

    # Peaks in May (~doy 135), troughs in January.
    temp = 27.0 + 6.5 * math.sin(2 * math.pi * (doy - 105) / 365.0)

    # Monsoon window, roughly 10 June to 30 September.
    monsoon = 0.0
    if 161 <= doy <= 273:
        monsoon = math.sin(math.pi * (doy - 161) / 112.0)

    # A stable per-location, per-day jitter so nearby days differ without
    # randomness leaking into tests.
    seed = (doy * 7919 + int(abs(lat) * 100) * 131 + int(abs(lon) * 100) * 17) % 1000
    jitter = (seed / 1000.0) - 0.5

    rain_prob = max(0.0, min(1.0, monsoon * 0.85 + jitter * 0.25))
    rain_mm = round(max(0.0, monsoon * 22.0 * (0.55 + jitter)), 1)
    temp = round(temp - (rain_mm * 0.12) + jitter * 2.0, 1)

    return Weather(on=day, temp_c=temp, rain_mm=rain_mm, rain_prob=round(rain_prob, 2))


def weather_effect(w: Weather, category_key: str) -> tuple[float, str | None]:
    """Demand multiplier from weather, and the driver name if it dominates."""
    from .catalog import category

    sensitivity = category(category_key).rain_sensitivity
    if abs(sensitivity) < 0.01:
        return 0.0, None

    # Normalised against 20mm, which is a decisively wet day in Pune.
    intensity = min(1.0, w.rain_mm / 20.0)
    effect = sensitivity * intensity
    if abs(effect) < 0.05:
        return effect, None

    return effect, "Heavy rain forecast" if effect > 0 else "Rain suppressing demand"
