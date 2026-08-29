"""Seed a realistic demo world.

Every chart, forecast, score, and heatmap cell in the app is computed from this
data -- nothing in the UI is hardcoded. Realism matters for the same reason:
a forecast fitted on flat random noise produces a flat line, and the festival
and weather logic would have nothing to demonstrate.

So the generator models what a kirana store's sales actually look like:
per-SKU base velocity, a weekend lift, a salary-week bump at the start of the
month, category-specific weather and festival response, and a slow growth
trend, all with multiplicative noise.

Run:  python seed.py [--vendors 12] [--days 90] [--reset]
"""
from __future__ import annotations

import argparse
import math
import random
import sys
import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import delete, select

from app.core.db import Base, SessionLocal, engine
from app.models import (
    BargainPool,
    ConflictAudit,
    Forecast,
    InventoryItem,
    Lender,
    OtpChallenge,
    PoolMember,
    ScoreConsent,
    Supplier,
    SyncEvent,
    Transaction,
    Vendor,
)
from app.services.catalog import shelf_life_for
from app.services.signals import festival_intensity, forecast_weather, weather_effect

RNG = random.Random(2026)

# Pune localities with real approximate coordinates, so the heatmap renders
# over a real map rather than an abstract grid.
LOCALITIES = [
    ("Kothrud", 18.5074, 73.8077),
    ("Deccan Gymkhana", 18.5158, 73.8449),
    ("Shivajinagar", 18.5308, 73.8475),
    ("Camp", 18.5116, 73.8770),
    ("Hadapsar", 18.5089, 73.9260),
    ("Aundh", 18.5590, 73.8078),
    ("Viman Nagar", 18.5679, 73.9143),
    ("Katraj", 18.4529, 73.8654),
]

# Composed rather than listed, so a denser seed does not repeat store names
# across localities and make the heatmap look duplicated.
_STORE_PREFIX = [
    "Kumar", "Sai", "Ganesh", "Jai Bhavani", "Shree Datta", "New Maharashtra",
    "Balaji", "Om Sai", "Gurukrupa", "Annapurna", "Vighnaharta", "Laxmi",
    "Tulja Bhavani", "Sadguru", "Mauli", "Siddhivinayak", "Krishna", "Shivneri",
    "Jyotiba", "Panchsheel",
]
_STORE_SUFFIX = [
    "General Stores", "Kirana", "Provision Store", "Super Shoppe",
    "Traders", "Daily Needs",
]


def _store_name(i: int) -> str:
    return (
        f"{_STORE_PREFIX[i % len(_STORE_PREFIX)]} "
        f"{_STORE_SUFFIX[(i // len(_STORE_PREFIX)) % len(_STORE_SUFFIX)]}"
    )

OWNER_NAMES = [
    "Rakesh Kumar", "Sunita Pawar", "Ganesh Jadhav", "Meera Shinde",
    "Datta Kulkarni", "Prakash Deshmukh", "Anita More", "Sachin Gaikwad",
    "Vijay Patil", "Kavita Joshi", "Ramesh Bhosale", "Nilima Kadam",
]

# (sku, category, unit, cost, price, base daily velocity)
PRODUCTS = [
    ("Milk",          "dairy",         "pkt", 24,  28,  42),
    ("Curd",          "dairy",         "pkt", 20,  25,  16),
    ("Paneer",        "dairy",         "pc",  70,  85,   5),
    ("Butter",        "dairy",         "pc",  52,  60,   7),
    ("Eggs",          "dairy",         "pc",   6,   8,  38),
    ("Bread",         "bakery",        "pc",  32,  40,  14),
    ("Rice",          "staples",       "kg",  52,  62,  22),
    ("Wheat Flour",   "staples",       "kg",  38,  46,  18),
    ("Sugar",         "staples",       "kg",  42,  48,  12),
    ("Tea",           "staples",       "pkt", 130, 150,  6),
    ("Toor Dal",      "staples",       "kg",  118, 138,  8),
    ("Cooking Oil",   "staples",       "l",   140, 162,  9),
    ("Salt",          "staples",       "kg",  20,  24,   5),
    ("Onion",         "produce",       "kg",  28,  36,  26),
    ("Potato",        "produce",       "kg",  24,  32,  22),
    ("Tomato",        "produce",       "kg",  30,  40,  18),
    ("Biscuits",      "snacks",        "pkt", 10,  12,  34),
    ("Namkeen",       "snacks",        "pkt", 38,  45,  11),
    ("Soft Drink",    "beverages",     "btl", 32,  40,  15),
    ("Soap",          "personal_care", "pc",  34,  42,   9),
    ("Shampoo",       "personal_care", "pkt",  3,   5,  20),
    ("Detergent",     "household",     "kg",  95, 115,   6),
    ("Umbrella",      "monsoon",       "pc", 180, 240,   2),
    ("Ladoo",         "sweets",        "kg", 220, 280,   4),
]

SUPPLIERS = [
    ("Market Yard Wholesale", "mandi", 18.4890, 73.8710, "Market Yard",
     ["produce", "staples"], 1, 2000),
    ("Gultekdi Mandi", "mandi", 18.4936, 73.8656, "Gultekdi",
     ["produce"], 1, 1500),
    ("Balaji Distributors", "distributor", 18.5121, 73.8290, "Kothrud",
     ["dairy", "bakery", "snacks"], 2, 3000),
    ("Shree FMCG Agencies", "distributor", 18.5325, 73.8501, "Shivajinagar",
     ["snacks", "beverages", "personal_care", "household"], 2, 5000),
    ("Pune Dairy Supply", "distributor", 18.5602, 73.8110, "Aundh",
     ["dairy"], 1, 1200),
    ("Ganesh Trading Co", "distributor", 18.5098, 73.9240, "Hadapsar",
     ["staples", "household"], 3, 4000),
]

LENDERS = [
    ("Bharat Micro Finance", "mfi", "credit@bharatmfi.example"),
    ("Sahyadri NBFC", "nbfc", "lending@sahyadri.example"),
    ("Pune Urban Co-op Bank", "bank", "msme@puneurban.example"),
]


def as_utc(d: date, hour: int = 12) -> datetime:
    return datetime(d.year, d.month, d.day, hour, tzinfo=timezone.utc)


def daily_quantity(
    *, base: float, day: date, category: str, lat: float, lon: float, scale: float
) -> float:
    """One day's sales for one SKU, shaped by every signal the model uses."""
    qty = base * scale

    # Weekends are busier for a neighbourhood store.
    if day.weekday() >= 5:
        qty *= 1.35
    elif day.weekday() == 4:
        qty *= 1.12

    # Salary week: the first days of the month see heavier restocking.
    if day.day <= 5:
        qty *= 1.18
    elif day.day >= 27:
        qty *= 0.88

    fest, _ = festival_intensity(day, category)
    qty *= 1.0 + fest

    wx = forecast_weather(day, lat, lon)
    effect, _ = weather_effect(wx, category)
    qty *= 1.0 + effect

    # Gentle growth, so turnover trends and the Health Score has something to
    # describe beyond a flat line.
    age = (date.today() - day).days
    qty *= 1.0 + (0.0015 * (90 - min(age, 90)))

    qty *= RNG.uniform(0.78, 1.22)
    return max(0.0, qty)


def _recompute_reorder_points(db) -> int:
    """Populate every item's dynamic reorder point via the live service."""
    from collections import defaultdict

    from app.services.forecasting import forecast_item
    from app.services.safety_stock import compute_reorder_point

    vendors = db.scalars(select(Vendor)).all()
    scored = 0

    for vendor in vendors:
        items = db.scalars(
            select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
        ).all()

        for item in items:
            rows = db.execute(
                select(Transaction.occurred_at, Transaction.qty).where(
                    Transaction.item_id == item.id, Transaction.type == "sale"
                )
            ).all()
            history = [(ts.date(), float(q)) for ts, q in rows]
            if not history:
                continue

            end = max(d for d, _ in history)
            window_start = end - timedelta(days=20)
            totals = defaultdict(float)
            for d, q in history:
                if d >= window_start:
                    totals[d] += q
            daily = [totals.get(window_start + timedelta(days=i), 0.0) for i in range(21)]

            fc = forecast_item(
                item_id=str(item.id), sku_name=item.sku_name,
                category_key=item.category, history=history,
                horizon_days=max(3, vendor.supplier_lead_days),
                lat=vendor.lat or 18.52, lon=vendor.lon or 73.86,
            )

            advice = compute_reorder_point(
                recent_daily_demand=daily,
                category_key=item.category,
                lead_days=vendor.supplier_lead_days,
                current_qty=item.current_qty,
                forecast_daily=[d.predicted for d in fc.days],
            )
            item.reorder_point = advice.reorder_point
            scored += 1

        db.commit()

    return scored


def seed(vendor_count: int, days: int, reset: bool) -> None:
    Base.metadata.create_all(engine)
    db = SessionLocal()

    try:
        if reset:
            for model in (
                ConflictAudit, SyncEvent, Forecast, Transaction, PoolMember,
                BargainPool, ScoreConsent, InventoryItem, OtpChallenge,
                Supplier, Lender, Vendor,
            ):
                db.execute(delete(model))
            db.commit()
            print("cleared existing data")

        if db.scalar(select(Vendor).limit(1)) is not None:
            print("database already seeded; pass --reset to rebuild")
            return

        for name, kind, lat, lon, locality, cats, lead, moq in SUPPLIERS:
            db.add(Supplier(
                name=name, kind=kind, lat=lat, lon=lon, locality=locality,
                city="Pune", categories=cats, lead_days=lead,
                min_order_value=moq, rating=round(RNG.uniform(3.8, 4.8), 1),
            ))

        for name, kind, contact in LENDERS:
            db.add(Lender(name=name, kind=kind, contact=contact))

        db.commit()

        today = date.today()
        start = today - timedelta(days=days)
        total_txns = 0

        for i in range(vendor_count):
            locality_index = i % len(LOCALITIES)
            locality, base_lat, base_lon = LOCALITIES[locality_index]
            # Shared delivery-day phase for every store in this locality.
            locality_phase = locality_index % 3
            # Scatter stores within their locality, but tightly enough that
            # neighbours land in the same ~1.1km heatmap cell. Wider scatter
            # splits a locality across cells and every cell then falls under
            # the k-anonymity floor and is suppressed.
            lat = round(base_lat + RNG.uniform(-0.003, 0.003), 6)
            lon = round(base_lon + RNG.uniform(-0.003, 0.003), 6)

            # Store size multiplier, so the heatmap and Health Score show real
            # spread rather than a dozen identical shops.
            scale = RNG.uniform(0.55, 1.75)

            vendor = Vendor(
                id=uuid.uuid4(),
                name=OWNER_NAMES[i % len(OWNER_NAMES)],
                store_name=_store_name(i),
                phone=f"98765{10000 + i:05d}",
                language_pref=RNG.choice(["hi", "hi", "mr", "en"]),
                lat=lat, lon=lon, locality=locality, city="Pune",
                supplier_lead_days=RNG.choice([1, 2, 2, 3]),
            )
            db.add(vendor)
            db.flush()

            # Each store carries a subset of the catalogue.
            catalogue = RNG.sample(PRODUCTS, k=RNG.randint(14, len(PRODUCTS)))

            for sku, cat, unit, cost, price, base in catalogue:
                shelf = shelf_life_for(cat)
                item = InventoryItem(
                    id=uuid.uuid4(),
                    vendor_id=vendor.id,
                    sku_name=sku,
                    category=cat,
                    unit=unit,
                    unit_cost=round(cost * RNG.uniform(0.95, 1.05), 2),
                    unit_price=round(price * RNG.uniform(0.97, 1.06), 2),
                    current_qty=0,
                    shelf_life_days=shelf,
                )
                db.add(item)
                db.flush()

                stock = base * scale * RNG.uniform(2.0, 4.0)
                restock_gap = 2 if shelf and shelf <= 4 else RNG.randint(4, 8)

                # Stores in a locality are served by the same distributor on the
                # same delivery days, so they run low together. Giving each store
                # an independent restock phase would decorrelate shortages and
                # collective bargaining would never find three vendors short of
                # the same SKU -- the supply mechanism is what makes pooling
                # possible, so the simulation has to reproduce it.
                next_restock = (locality_phase + RNG.randint(0, 1)) % restock_gap

                for offset in range(days + 1):
                    day = start + timedelta(days=offset)
                    # Today is in progress, so it carries a partial day's sales.
                    # A full day would make the dashboard's "today" figure look
                    # like a closing total at 10am.
                    partial = 0.45 if day == today else 1.0

                    if offset >= next_restock:
                        # Restock covers the gap plus a buffer.
                        amount = round(base * scale * restock_gap * RNG.uniform(1.1, 1.5), 1)
                        stock += amount
                        db.add(Transaction(
                            vendor_id=vendor.id, item_id=item.id, type="restock",
                            qty=amount, unit_value=item.unit_cost,
                            source=RNG.choice(["ocr", "ocr", "manual"]),
                            confidence=round(RNG.uniform(0.82, 0.99), 2),
                            occurred_at=as_utc(day, 8),
                        ))
                        total_txns += 1
                        next_restock = offset + restock_gap

                    want = daily_quantity(
                        base=base, day=day, category=cat, lat=lat, lon=lon, scale=scale
                    ) * partial
                    sold = round(min(want, stock), 1)
                    if sold > 0:
                        stock -= sold
                        db.add(Transaction(
                            vendor_id=vendor.id, item_id=item.id, type="sale",
                            qty=sold, unit_value=item.unit_price,
                            source=RNG.choices(
                                ["voice", "manual", "voice"], weights=[5, 3, 2]
                            )[0],
                            confidence=round(RNG.uniform(0.74, 1.0), 2),
                            occurred_at=as_utc(day, 19),
                        ))
                        total_txns += 1

                    # Perishables spoil when they outlive their shelf life.
                    if shelf and shelf <= 7 and RNG.random() < 0.16:
                        spoiled = round(stock * RNG.uniform(0.03, 0.11), 1)
                        if spoiled > 0:
                            stock -= spoiled
                            db.add(Transaction(
                                vendor_id=vendor.id, item_id=item.id, type="wastage",
                                qty=spoiled, unit_value=item.unit_cost,
                                source="manual", confidence=1.0,
                                occurred_at=as_utc(day, 21),
                            ))
                            total_txns += 1

                item.current_qty = round(max(0.0, stock), 1)
                if shelf:
                    # Spread expiry across the window so the expiry board has
                    # items in every urgency band on day one.
                    item.expires_on = as_utc(today + timedelta(days=RNG.randint(-1, shelf)))

            db.commit()
            print(f"  seeded {vendor.store_name:28} {locality:18} {len(catalogue)} SKUs")

        # Reorder points are derived, not authored. Computing them here through
        # the same service the API uses keeps the seeded world internally
        # consistent: low-stock flags, pool candidates and restock advice all
        # agree with the transaction history that produced them.
        print("\ncomputing dynamic reorder points...")
        print(f"  {_recompute_reorder_points(db)} items scored")

        print(f"\n{vendor_count} vendors, {days} days, {total_txns:,} transactions")
        print(f"{len(SUPPLIERS)} suppliers, {len(LENDERS)} lenders")

        first = db.scalar(select(Vendor).order_by(Vendor.created_at))
        print(f"\nDemo login phone: {first.phone}  (OTP is returned by /auth/otp/request)")

    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed the Vendor360 demo world")
    # 8 localities x 5 stores. Three per locality clears the heatmap's
    # k-anonymity floor but leaves collective bargaining almost never
    # triggering, since a pool needs three vendors short of the *same*
    # SKU. Five matches the density the PRD's distributor persona
    # describes and makes both features exercise real data.
    parser.add_argument("--vendors", type=int, default=40)
    parser.add_argument("--days", type=int, default=90)
    parser.add_argument("--reset", action="store_true")
    args = parser.parse_args()

    seed(args.vendors, args.days, args.reset)
