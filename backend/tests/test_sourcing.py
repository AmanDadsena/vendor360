"""Ranking suppliers for a shortfall (TC-R**).

The cases here mostly exist to defend one claim: the headline unit price is
not the cost. Pack sizes and minimum orders decide what a vendor actually
pays, and a ranking that ignores them recommends the wrong wholesaler.
"""
from __future__ import annotations

import uuid

import pytest

from app.models import CatalogEntry, Supplier, VendorDistributor
from app.services.ordering import amend_lines, build_order, transition
from app.services.sourcing import days_of_cover, haversine_km, rank_options


def _supplier(db, name, *, lat=18.52, lon=73.86, lead=1):
    s = Supplier(
        id=uuid.uuid4(),
        name=name,
        kind="distributor",
        lat=lat,
        lon=lon,
        locality="Kothrud",
        city="Pune",
        categories=["dairy"],
        lead_days=lead,
        rating=4.0,
    )
    db.add(s)
    db.commit()
    return s


def _connect(db, vendor, supplier):
    link = VendorDistributor(
        id=uuid.uuid4(),
        vendor_id=vendor.id,
        supplier_id=supplier.id,
        status="active",
        shares_demand=True,
        scope_categories=["dairy"],
    )
    db.add(link)
    db.commit()
    return link


def _list(
    db,
    supplier,
    *,
    pack_size,
    pack_price,
    moq=1,
    lead=None,
    sku="Milk",
    category="dairy",
    unit="pkt",
):
    entry = CatalogEntry(
        id=uuid.uuid4(),
        supplier_id=supplier.id,
        sku_name=sku,
        category=category,
        unit=unit,
        pack_size=pack_size,
        pack_price=pack_price,
        moq_packs=moq,
        lead_days=lead,
    )
    db.add(entry)
    db.commit()
    return entry


# ------------------------------------------------------------ TC-R01 basics
def test_tc_r01_unconnected_suppliers_are_never_quoted(db, vendor, milk):
    """A price the vendor has no relationship to act on is not an option."""
    stranger = _supplier(db, "Stranger Traders")
    _list(db, stranger, pack_size=12, pack_price=200)

    options = rank_options(
        db, vendor=vendor, item=milk, shortfall=24, cover_days=5
    )

    assert options == []


def test_tc_r01_out_of_stock_listings_are_dropped(db, vendor, milk):
    supplier = _supplier(db, "Empty Traders")
    _connect(db, vendor, supplier)
    entry = _list(db, supplier, pack_size=12, pack_price=200)
    entry.available_packs = 0
    db.commit()

    assert rank_options(db, vendor=vendor, item=milk, shortfall=24, cover_days=5) == []


def test_untracked_stock_is_not_treated_as_empty(db, vendor, milk):
    """`available_packs` of None means "not counted", not "none left"."""
    supplier = _supplier(db, "Untracked Traders")
    _connect(db, vendor, supplier)
    _list(db, supplier, pack_size=12, pack_price=200)

    assert len(rank_options(db, vendor=vendor, item=milk, shortfall=24, cover_days=5)) == 1


# ------------------------------------------- TC-R02 MOQ-aware landed cost
def test_tc_r02_moq_beats_headline_unit_price(db, vendor, milk):
    """The cheaper per-unit price loses when its minimum order triples the bill.

    Cheap Traders: ₹22/pkt but a 5-case minimum → 60 pkt for ₹1320.
    Fair Traders:  ₹24/pkt with no minimum     → 24 pkt for ₹576.

    A vendor needing 24 packets should be sent to Fair.
    """
    cheap = _supplier(db, "Cheap Traders")
    fair = _supplier(db, "Fair Traders")
    _connect(db, vendor, cheap)
    _connect(db, vendor, fair)

    _list(db, cheap, pack_size=12, pack_price=264, moq=5)  # ₹22/pkt
    _list(db, fair, pack_size=12, pack_price=288, moq=1)   # ₹24/pkt

    options = rank_options(db, vendor=vendor, item=milk, shortfall=24, cover_days=5)

    assert options[0].supplier.name == "Fair Traders"
    assert options[0].plan.cost == pytest.approx(576.0)

    loser = next(o for o in options if o.supplier.name == "Cheap Traders")
    assert loser.plan.cost == pytest.approx(1320.0)
    assert loser.plan.moq_applied is True


def test_tc_r02_cheaper_wins_when_the_minimum_is_reachable(db, vendor, milk):
    """Same two suppliers, but now the shop needs enough to clear the minimum."""
    cheap = _supplier(db, "Cheap Traders")
    fair = _supplier(db, "Fair Traders")
    _connect(db, vendor, cheap)
    _connect(db, vendor, fair)

    _list(db, cheap, pack_size=12, pack_price=264, moq=5)
    _list(db, fair, pack_size=12, pack_price=288, moq=1)

    options = rank_options(db, vendor=vendor, item=milk, shortfall=60, cover_days=10)

    assert options[0].supplier.name == "Cheap Traders"


def test_tc_r02_forced_surplus_is_reported_not_hidden(db, vendor, milk):
    supplier = _supplier(db, "Case Traders")
    _connect(db, vendor, supplier)
    _list(db, supplier, pack_size=12, pack_price=288)

    option = rank_options(
        db, vendor=vendor, item=milk, shortfall=20, cover_days=5
    )[0]

    assert option.plan.packs == 2
    assert option.plan.surplus == 4
    assert any("extra" in r for r in option.reasons)


# ------------------------------------------------- TC-R03 speed vs. price
def test_tc_r03_a_supplier_who_arrives_too_late_is_demoted(db, vendor, milk):
    """Cheapest is not cheapest if the shelf empties before it arrives."""
    slow = _supplier(db, "Slow Traders", lead=5)
    quick = _supplier(db, "Quick Traders", lead=1)
    _connect(db, vendor, slow)
    _connect(db, vendor, quick)

    _list(db, slow, pack_size=12, pack_price=240, lead=5)   # ₹20/pkt
    _list(db, quick, pack_size=12, pack_price=288, lead=1)  # ₹24/pkt

    options = rank_options(db, vendor=vendor, item=milk, shortfall=24, cover_days=2)

    assert options[0].supplier.name == "Quick Traders"
    late = next(o for o in options if o.supplier.name == "Slow Traders")
    assert late.arrives_in_time is False
    assert any("stock lasts" in r for r in late.reasons)


def test_tc_r03_slow_and_cheap_wins_when_there_is_time(db, vendor, milk):
    slow = _supplier(db, "Slow Traders", lead=5)
    quick = _supplier(db, "Quick Traders", lead=1)
    _connect(db, vendor, slow)
    _connect(db, vendor, quick)

    _list(db, slow, pack_size=12, pack_price=240, lead=5)
    _list(db, quick, pack_size=12, pack_price=288, lead=1)

    options = rank_options(db, vendor=vendor, item=milk, shortfall=24, cover_days=30)

    assert options[0].supplier.name == "Slow Traders"


# ------------------------------------------------------ TC-R04 reliability
def test_tc_r04_a_proven_supplier_outranks_an_unknown_one_at_equal_price(
    db, vendor, milk
):
    proven = _supplier(db, "Proven Traders")
    unknown = _supplier(db, "Unknown Traders")
    _connect(db, vendor, proven)
    _connect(db, vendor, unknown)

    proven_entry = _list(db, proven, pack_size=12, pack_price=288)
    _list(db, unknown, pack_size=12, pack_price=288)

    # Two fully delivered orders give Proven a 100% record.
    for _ in range(2):
        order = build_order(
            db,
            vendor=vendor,
            supplier=proven,
            lines=[{"catalog_entry_id": proven_entry.id, "packs": 4}],
        )
        for status in ("placed", "confirmed", "dispatched"):
            transition(db, order, status, actor_role="vendor")
        amend_lines(order, {}, "packs_delivered")
        transition(db, order, "delivered", actor_role="vendor")
        db.commit()

    options = rank_options(db, vendor=vendor, item=milk, shortfall=24, cover_days=10)

    assert options[0].supplier.name == "Proven Traders"
    assert any("fills 100%" in r for r in options[0].reasons)
    assert any("no order history" in r for r in options[1].reasons)


def test_tc_r04_a_bad_fill_rate_is_stated_plainly(db, vendor, milk):
    flaky = _supplier(db, "Flaky Traders")
    _connect(db, vendor, flaky)
    entry = _list(db, flaky, pack_size=12, pack_price=288)

    for delivered in (5, 5):
        order = build_order(
            db,
            vendor=vendor,
            supplier=flaky,
            lines=[{"catalog_entry_id": entry.id, "packs": 10}],
        )
        for status in ("placed", "confirmed", "dispatched"):
            transition(db, order, status, actor_role="vendor")
        amend_lines(order, {order.lines[0].id: delivered}, "packs_delivered")
        transition(db, order, "delivered", actor_role="vendor")
        db.commit()

    option = rank_options(db, vendor=vendor, item=milk, shortfall=24, cover_days=10)[0]

    assert option.fill == pytest.approx(0.5)
    assert any("only fills 50%" in r for r in option.reasons)


# ---------------------------------------------------------- TC-R05 reasons
def test_tc_r05_the_leader_explains_itself_against_the_runner_up(db, vendor, milk):
    best = _supplier(db, "Best Traders", lead=1)
    other = _supplier(db, "Other Traders", lead=3)
    _connect(db, vendor, best)
    _connect(db, vendor, other)

    _list(db, best, pack_size=12, pack_price=240, lead=1)   # ₹20/pkt
    _list(db, other, pack_size=12, pack_price=288, lead=3)  # ₹24/pkt

    leader = rank_options(db, vendor=vendor, item=milk, shortfall=24, cover_days=10)[0]

    assert leader.supplier.name == "Best Traders"
    assert any("cheaper per pkt" in r for r in leader.reasons)
    assert any("sooner" in r for r in leader.reasons)
    # Never more than three: a wall of justification is not a justification.
    assert len(leader.reasons) <= 3


# ---------------------------------------------------------------- helpers
def test_days_of_cover_is_undefined_when_nothing_sells():
    assert days_of_cover(50, 0) is None
    assert days_of_cover(50, 10) == 5


def test_haversine_matches_a_known_pune_distance():
    # Kothrud to Hadapsar, roughly 13 km across the city.
    km = haversine_km(18.5074, 73.8077, 18.5089, 73.9260)
    assert 11 < km < 14


# ------------------------------------- TC-R06 perishability and urgency
def test_tc_r06_surplus_rice_is_forgiven_but_surplus_milk_is_not(db, vendor):
    """The same over-order is a small cost in staples and a large one in dairy."""
    from app.models import InventoryItem
    from app.services.sourcing import salvage_rate

    assert salvage_rate("staples") > salvage_rate("dairy")
    assert salvage_rate("dairy") < 0.3
    # Non-perishables recover most of their value; they simply sell later.
    assert salvage_rate("household") > 0.8

    rice = InventoryItem(
        id=uuid.uuid4(),
        vendor_id=vendor.id,
        sku_name="Rice",
        category="staples",
        current_qty=10,
        unit="kg",
        unit_cost=50,
        unit_price=58,
        reorder_point=20,
    )
    db.add(rice)
    db.commit()

    bulk = _supplier(db, "Bulk Traders")
    small = _supplier(db, "Small Traders")
    _connect(db, vendor, bulk)
    _connect(db, vendor, small)

    # ₹50/kg either way, but Bulk only sells 25 kg sacks against a 10 kg need.
    _list(
        db, bulk, pack_size=25, pack_price=1250,
        sku="Rice", category="staples", unit="kg",
    )
    _list(
        db, small, pack_size=10, pack_price=520,
        sku="Rice", category="staples", unit="kg",
    )

    options = rank_options(db, vendor=vendor, item=rice, shortfall=10, cover_days=20)
    by_name = {o.supplier.name: o for o in options}
    bulk_option = by_name["Bulk Traders"]

    assert bulk_option.plan.surplus == 15
    # 15 kg of surplus rice recovers 85% of its value, so the effective cost is
    # ₹61/kg rather than the ₹125/kg a naive "outlay ÷ need" would report.
    assert bulk_option.unit_landed == pytest.approx(61.25)

    # The identical surplus in dairy would be written off almost entirely.
    milk_bulk = _supplier(db, "Milk Bulk Traders")
    _connect(db, vendor, milk_bulk)
    _list(db, milk_bulk, pack_size=25, pack_price=1250, sku="Curd")
    curd = InventoryItem(
        id=uuid.uuid4(),
        vendor_id=vendor.id,
        sku_name="Curd",
        category="dairy",
        current_qty=10,
        unit="pkt",
        reorder_point=20,
    )
    db.add(curd)
    db.commit()

    curd_option = rank_options(
        db, vendor=vendor, item=curd, shortfall=10, cover_days=20
    )[0]
    assert curd_option.unit_landed == pytest.approx(113.75)
    assert curd_option.unit_landed > bulk_option.unit_landed


def test_tc_r06_urgency_collapses_as_cover_grows():
    from app.services.sourcing import urgency

    assert urgency(0) == 1.0            # out of stock today
    assert urgency(5) == pytest.approx(0.5)
    assert urgency(30) == 0.0           # a month of cover: buy on price
    assert urgency(None) == 0.0         # nothing selling: nothing urgent
