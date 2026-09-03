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

from sqlalchemy import delete, func, select

from app.core.db import Base, SessionLocal, engine
from app.models import (
    BargainPool,
    CatalogEntry,
    ConflictAudit,
    DistributorUser,
    Forecast,
    InventoryItem,
    LedgerEntry,
    Lender,
    OrderEvent,
    OtpChallenge,
    PoolMember,
    PurchaseOrder,
    PurchaseOrderLine,
    ScoreConsent,
    Supplier,
    SyncEvent,
    Transaction,
    Vendor,
    VendorDistributor,
)
from app.services.catalog import shelf_life_for
from app.services.signals import festival_intensity, forecast_weather, weather_effect
from app.services.sourcing import haversine_km

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

# Coverage is deliberate: every category a shop stocks is carried by at least
# two wholesalers, so the sourcing screen always has something to rank against
# something else. A single-supplier category would render as a list of one,
# which teaches a vendor the ranking is decorative.
SUPPLIERS = [
    ("Market Yard Wholesale", "mandi", 18.4890, 73.8710, "Market Yard",
     ["produce", "staples"], 1, 2000),
    ("Gultekdi Mandi", "mandi", 18.4936, 73.8656, "Gultekdi",
     ["produce", "staples"], 1, 1500),
    ("Balaji Distributors", "distributor", 18.5121, 73.8290, "Kothrud",
     ["dairy", "bakery", "snacks", "sweets"], 2, 3000),
    ("Shree FMCG Agencies", "distributor", 18.5325, 73.8501, "Shivajinagar",
     ["snacks", "beverages", "personal_care", "household"], 2, 5000),
    ("Pune Dairy Supply", "distributor", 18.5602, 73.8110, "Aundh",
     ["dairy", "bakery"], 1, 1200),
    ("Ganesh Trading Co", "distributor", 18.5098, 73.9240, "Hadapsar",
     ["staples", "household", "personal_care"], 3, 4000),
    ("Deccan Consumer Products", "distributor", 18.5164, 73.8412, "Deccan Gymkhana",
     ["snacks", "beverages", "sweets", "personal_care"], 2, 2500),
    ("Sahyadri Seasonal Goods", "distributor", 18.4571, 73.8620, "Katraj",
     ["monsoon", "household", "produce"], 3, 1800),
    ("Viman Nagar Cash & Carry", "distributor", 18.5651, 73.9128, "Viman Nagar",
     ["staples", "dairy", "snacks", "beverages", "household", "monsoon"], 2, 6000),
]

LENDERS = [
    ("Bharat Micro Finance", "mfi", "credit@bharatmfi.example"),
    ("Sahyadri NBFC", "nbfc", "lending@sahyadri.example"),
    ("Pune Urban Co-op Bank", "bank", "msme@puneurban.example"),
]

# The person who answers the phone at each wholesaler, in SUPPLIERS order.
# Phones sit in a 9820x block so they never collide with the 98765x vendor
# range -- a number that is both a shop and a wholesaler cannot sign in.
DISTRIBUTOR_STAFF = [
    ("Ashok Rane", "9820010001"),
    ("Sunil Gaikwad", "9820010002"),
    ("Anil Shah", "9820010003"),
    ("Farhan Qureshi", "9820010004"),
    ("Deepak Salunkhe", "9820010005"),
    ("Ganesh Bhandari", "9820010006"),
    ("Rohit Chavan", "9820010007"),
    ("Sameer Kulkarni", "9820010008"),
    ("Nitin Wagh", "9820010009"),
]

# How each unit is cased at wholesale: (pack size, minimum packs).
# Real distributors sell crates and sacks, and these are the sizes a Pune
# wholesaler actually quotes.
PACKING = {
    "pkt": [(12, 1), (24, 1), (48, 2)],
    "kg": [(5, 2), (10, 1), (25, 1)],
    "l": [(5, 2), (15, 1)],
    "pc": [(12, 1), (24, 1), (48, 2)],
    "btl": [(24, 1)],
}


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


def _best_demo_distributor(db) -> DistributorUser:
    """The wholesaler whose console has the most to show.

    Same reasoning as `_stage_demo_shop`: the seeded world is rich in
    aggregate, but any single account can land on a quiet corner of it. The
    first-created supplier is a produce mandi whose shops are all well stocked
    -- nothing waiting, nothing at risk, nothing overdue -- which makes the
    flagship screens look broken rather than calm.

    Nothing is fabricated here. This picks the account that already has the
    fullest picture, so the demo login opens on real work.
    """
    from app.services.distributor_intel import at_risk_shops

    best, best_score = None, -1
    for user in db.scalars(select(DistributorUser).order_by(DistributorUser.created_at)):
        supplier = user.supplier
        waiting = db.scalar(
            select(func.count(PurchaseOrder.id)).where(
                PurchaseOrder.supplier_id == supplier.id,
                PurchaseOrder.status.in_(("placed", "confirmed", "dispatched")),
            )
        ) or 0
        score = len(at_risk_shops(db, supplier)) * 2 + waiting
        if score > best_score:
            best, best_score = user, score
    return best


def _warm_forecast_cache(db, horizon_days: int = 14) -> int:
    """Precompute forecasts for every item that a distributor might aggregate.

    The demand outlook fits a model per (shop x SKU). Cold, that is ten
    seconds and past the client's read timeout; warm, it is a tenth of a
    second. Warming here means a fresh clone is fast on the very first load
    rather than after someone has already waited once.

    Fourteen days so both the one-week and two-week horizons hit.
    """
    from app.services import forecast_cache

    items = db.scalars(select(InventoryItem)).all()

    def history_for(item):
        rows = db.execute(
            select(Transaction.occurred_at, Transaction.qty).where(
                Transaction.item_id == item.id, Transaction.type == "sale"
            )
        ).all()
        return [(ts.date(), float(q)) for ts, q in rows]

    computed = forecast_cache.warm(
        db, items, horizon_days=horizon_days, history_for=history_for
    )
    db.commit()
    return computed


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


def _stage_demo_shop(db, vendor: Vendor) -> int:
    """Guarantee the demo login has something to demonstrate.

    Across the seeded world about one item in ten sits below its reorder point
    and the median shop has two -- which is realistic, and which by chance
    leaves roughly one shop in six with none at all. That is fine for the
    aggregate and bad for the first screen a reviewer opens.

    So the demo shop specifically is drawn down: a few items pushed just under
    the line, and one taken close to empty so the at-risk and sourcing paths
    have a worked example. The stock is reduced, not the reorder point --
    those stay derived from real history, and the arithmetic on screen still
    reconciles.
    """
    items = db.scalars(
        select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
    ).all()
    if not items:
        return 0

    # Prefer fast-moving, restockable lines: the ones a shopkeeper would
    # actually be reordering on a Tuesday.
    ranked = sorted(
        (i for i in items if i.reorder_point > 0),
        key=lambda i: -i.reorder_point,
    )

    staged = 0
    for index, item in enumerate(ranked[:5]):
        if index == 0:
            # Nearly out: this is the one that shows up as at-risk to whichever
            # wholesaler supplies it, and drives the urgent sourcing case.
            item.current_qty = round(item.reorder_point * 0.15, 1)
        else:
            item.current_qty = round(item.reorder_point * RNG.uniform(0.45, 0.9), 1)
        staged += 1

    return staged


def _seed_marketplace(db, today: date) -> tuple[int, int, int]:
    """Wire up the two-sided half: logins, price lists, connections, orders.

    Built after the vendors and their transaction history exist, because
    everything here is derived from them -- a connection points at a real
    shop, and an order's lines are priced from a real catalogue.

    Returns (catalogue lines, connections, orders).
    """
    suppliers = db.scalars(select(Supplier).order_by(Supplier.created_at)).all()
    vendors = db.scalars(select(Vendor).order_by(Vendor.created_at)).all()
    products = {p[0]: p for p in PRODUCTS}

    # ------------------------------------------------------------- logins
    for supplier, (name, phone) in zip(suppliers, DISTRIBUTOR_STAFF):
        supplier.phone = phone
        db.add(
            DistributorUser(
                supplier_id=supplier.id,
                name=name,
                phone=phone,
                language_pref=RNG.choice(["hi", "mr", "en"]),
            )
        )
    db.flush()

    # ----------------------------------------------------------- catalogues
    catalog_count = 0
    listings: dict[uuid.UUID, list[CatalogEntry]] = {}

    for supplier in suppliers:
        entries: list[CatalogEntry] = []
        for sku, cat, unit, cost, _price, _base in PRODUCTS:
            if cat not in (supplier.categories or []):
                continue

            pack_size, moq = RNG.choice(PACKING.get(unit, [(12, 1)]))
            # Wholesalers differ by a few percent on the same goods, which is
            # what gives the sourcing screen something real to rank.
            spread = RNG.uniform(0.93, 1.05)
            entry = CatalogEntry(
                supplier_id=supplier.id,
                sku_name=sku,
                category=cat,
                unit=unit,
                pack_size=pack_size,
                pack_price=round(cost * pack_size * spread, 2),
                moq_packs=moq,
                lead_days=RNG.choice([None, None, supplier.lead_days, 1]),
                available_packs=RNG.choice([None, None, RNG.randint(20, 400)]),
            )
            db.add(entry)
            entries.append(entry)
            catalog_count += 1

        listings[supplier.id] = entries

    db.flush()

    # ---------------------------------------------------------- connections
    connections = 0
    vendor_links: dict[uuid.UUID, list[Supplier]] = {}

    for vendor in vendors:
        # A shop deals with the wholesalers who cover its aisles, preferring
        # the nearby ones -- which is how these relationships actually form.
        ranked = sorted(
            suppliers,
            key=lambda s: haversine_km(vendor.lat, vendor.lon, s.lat, s.lon),
        )
        chosen = ranked[: RNG.randint(2, 4)]
        vendor_links[vendor.id] = chosen

        for supplier in chosen:
            scope = sorted({e.category for e in listings.get(supplier.id, [])})
            # Most shops share their demand; a realistic minority does not, so
            # the distributor's consent gaps are visible on day one.
            shares = RNG.random() > 0.18
            db.add(
                VendorDistributor(
                    vendor_id=vendor.id,
                    supplier_id=supplier.id,
                    status="active",
                    shares_demand=shares,
                    scope_categories=scope,
                    credit_terms_days=RNG.choice([0, 0, 7, 7, 14, 21]),
                    credit_limit=RNG.choice([0, 10000, 25000]),
                    connected_at=as_utc(today - timedelta(days=RNG.randint(20, 120))),
                )
            )
            connections += 1

    db.flush()

    # -------------------------------------------------------------- orders
    # A spread across every status, so the distributor inbox, the vendor's
    # order list and the ledger all have something in them immediately.
    order_count = 0
    sequence = 0
    weights = [
        ("delivered", 52),
        ("placed", 14),
        ("confirmed", 12),
        ("dispatched", 10),
        ("cancelled", 6),
        ("draft", 6),
    ]
    statuses = [s for s, w in weights for _ in range(w)]

    for vendor in vendors:
        for _ in range(RNG.randint(2, 6)):
            supplier = RNG.choice(vendor_links[vendor.id])
            entries = listings.get(supplier.id) or []
            if not entries:
                continue

            status = RNG.choice(statuses)
            # Weighted towards recent. A flat 1-75 spread put every delivery
            # more than a week back, so the distributor's "delivered this
            # week" read zero and every rupee outstanding was also overdue --
            # a demo that looks simultaneously dead and alarming. Real order
            # books are dense at the near end.
            age = RNG.choice([
                RNG.randint(1, 6),    # this week
                RNG.randint(1, 6),
                RNG.randint(7, 21),   # this month
                RNG.randint(7, 21),
                RNG.randint(22, 75),  # history
            ])
            placed_at = as_utc(today - timedelta(days=age), 10)

            sequence += 1
            terms = RNG.choice([0, 7, 14])
            order = PurchaseOrder(
                code=f"PO-{sequence:04d}",
                vendor_id=vendor.id,
                supplier_id=supplier.id,
                status=status,
                payment_terms_days=terms,
                note=None,
            )
            db.add(order)
            db.flush()

            total = 0.0
            for entry in RNG.sample(entries, k=min(len(entries), RNG.randint(1, 4))):
                packs = float(RNG.randint(entry.moq_packs, entry.moq_packs + 6))
                unit_price = round(entry.pack_price / entry.pack_size, 2)

                confirmed = delivered = None
                if status in ("confirmed", "dispatched", "delivered"):
                    # Part-fills are the norm, not the exception, which is what
                    # gives fill rate something to measure.
                    confirmed = packs if RNG.random() > 0.22 else float(
                        max(1, int(packs * RNG.uniform(0.5, 0.9)))
                    )
                if status == "delivered":
                    delivered = confirmed

                effective = delivered if delivered is not None else (
                    confirmed if confirmed is not None else packs
                )
                line_total = round(effective * entry.pack_size * unit_price, 2)
                total += line_total

                item = db.scalar(
                    select(InventoryItem).where(
                        InventoryItem.vendor_id == vendor.id,
                        InventoryItem.sku_name == entry.sku_name,
                    )
                )
                spec = products.get(entry.sku_name)

                db.add(
                    PurchaseOrderLine(
                        order_id=order.id,
                        catalog_entry_id=entry.id,
                        item_id=item.id if item else None,
                        sku_name=entry.sku_name,
                        category=spec[1] if spec else entry.category,
                        unit=entry.unit,
                        pack_size=entry.pack_size,
                        unit_price=unit_price,
                        packs_ordered=packs,
                        packs_confirmed=confirmed,
                        packs_delivered=delivered,
                        line_total=line_total,
                    )
                )

            order.amount_total = round(total, 2)

            # Timestamps and the event journal, walked forward through the
            # states this order actually reached.
            reached = ["draft"]
            if status != "draft":
                order.placed_at = placed_at
                order.expected_at = placed_at + timedelta(days=supplier.lead_days)
                reached.append("placed")
            if status in ("confirmed", "dispatched", "delivered"):
                order.confirmed_at = placed_at + timedelta(hours=RNG.randint(1, 20))
                reached.append("confirmed")
            if status in ("dispatched", "delivered"):
                order.dispatched_at = order.confirmed_at + timedelta(hours=RNG.randint(2, 30))
                reached.append("dispatched")
            if status == "delivered":
                order.delivered_at = order.dispatched_at + timedelta(hours=RNG.randint(3, 36))
                reached.append("delivered")
            if status == "cancelled":
                order.cancelled_at = placed_at + timedelta(hours=RNG.randint(1, 40))
                reached.append("cancelled")

            previous = None
            for state in reached:
                db.add(
                    OrderEvent(
                        order_id=order.id,
                        actor_role="vendor" if state in ("draft", "placed") else "distributor",
                        from_status=previous,
                        to_status=state,
                        created_at=getattr(order, f"{state}_at", None) or placed_at,
                    )
                )
                previous = state

            # A delivered order becomes money owed, and most of it gets paid.
            if status == "delivered" and order.amount_total > 0:
                db.add(
                    LedgerEntry(
                        vendor_id=vendor.id,
                        supplier_id=supplier.id,
                        order_id=order.id,
                        kind="charge",
                        amount=order.amount_total,
                        due_on=order.delivered_at + timedelta(days=terms),
                        note=f"{order.code} delivered",
                        created_at=order.delivered_at,
                    )
                )
                # Most invoices get settled, and the ones that are not skew
                # old -- an unpaid bill is unpaid because it has been sitting.
                # A flat rate produced either everything overdue (at 32%) or
                # nothing overdue (at 18%), because payment had no relation to
                # age. Tying them makes the overdue figure a real minority.
                settled_odds = 0.94 if age <= 21 else 0.72
                if RNG.random() < settled_odds:
                    paid = order.amount_total if RNG.random() > 0.25 else round(
                        order.amount_total * RNG.uniform(0.4, 0.8), 2
                    )
                    order.amount_paid = paid
                    db.add(
                        LedgerEntry(
                            vendor_id=vendor.id,
                            supplier_id=supplier.id,
                            order_id=order.id,
                            kind="payment",
                            amount=paid,
                            note="Payment received",
                            created_at=order.delivered_at + timedelta(days=RNG.randint(1, 20)),
                        )
                    )

            order_count += 1

    db.commit()
    return catalog_count, connections, order_count


def seed(vendor_count: int, days: int, reset: bool) -> None:
    Base.metadata.create_all(engine)
    db = SessionLocal()

    try:
        if reset:
            # Ordered so a child table is always cleared before its parent.
            for model in (
                ConflictAudit, SyncEvent, Forecast, OrderEvent,
                PurchaseOrderLine, LedgerEntry, PurchaseOrder,
                Transaction, PoolMember, BargainPool, ScoreConsent,
                VendorDistributor, CatalogEntry, DistributorUser,
                InventoryItem, OtpChallenge, Supplier, Lender, Vendor,
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

        # Built last: connections point at real shops, and order lines are
        # priced from a real catalogue against real inventory rows.
        print("\nwiring the marketplace...")
        entries, links, orders = _seed_marketplace(db, today)
        print(f"  {entries} catalogue lines, {links} connections, {orders} orders")

        demo = db.scalar(select(Vendor).order_by(Vendor.created_at))
        staged = _stage_demo_shop(db, demo)
        db.commit()
        print(f"  {staged} items drawn down at {demo.store_name} for the demo login")

        # After the draw-down, so the cached forecasts reflect the stock the
        # app will actually open on.
        print("\nwarming the forecast cache...")
        print(f"  {_warm_forecast_cache(db)} items precomputed")

        print(f"\n{vendor_count} vendors, {days} days, {total_txns:,} transactions")
        print(f"{len(SUPPLIERS)} suppliers, {len(LENDERS)} lenders")

        first = db.scalar(select(Vendor).order_by(Vendor.created_at))
        staff = _best_demo_distributor(db)
        print("\nOTP is returned by /auth/otp/request — there is no SMS gateway.")
        print(f"  shop login:        {first.phone}   ({first.store_name})")
        print(f"  distributor login: {staff.phone}   ({staff.supplier.name})")

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
