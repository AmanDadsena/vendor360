"""What a distributor may and may not learn about the shops they supply (TC-D**).

The privacy cases here are the important ones. Vendor360 already refuses to
show a distributor an individual shop's sales through the heatmap; making that
distributor a trading counterparty must not quietly reopen the door.
"""
from __future__ import annotations

import uuid
from datetime import timedelta

import pytest

from app.core.db import utcnow
from app.models import (
    CatalogEntry,
    InventoryItem,
    Transaction,
    Vendor,
    VendorDistributor,
)
from app.services.distributor_intel import (
    MIN_SHOPS_FOR_AGGREGATE,
    at_risk_shops,
    book_summary,
    dead_lines,
    demand_outlook,
)


def _shop(db, name, phone, *, locality="Kothrud"):
    v = Vendor(
        id=uuid.uuid4(),
        name=name,
        store_name=f"{name} Stores",
        phone=phone,
        language_pref="hi",
        lat=18.52,
        lon=73.86,
        locality=locality,
    )
    db.add(v)
    db.commit()
    return v


def _stock(db, vendor, *, sku="Milk", category="dairy", qty=50, unit="pkt"):
    item = InventoryItem(
        id=uuid.uuid4(),
        vendor_id=vendor.id,
        sku_name=sku,
        category=category,
        current_qty=qty,
        unit=unit,
        unit_cost=24,
        unit_price=28,
        reorder_point=20,
    )
    db.add(item)
    db.commit()
    return item


def _sales(db, vendor, item, *, per_day=10.0, days=30):
    """A steady sales history, so the forecaster has something to work with."""
    for offset in range(days, 0, -1):
        db.add(
            Transaction(
                vendor_id=vendor.id,
                item_id=item.id,
                type="sale",
                qty=per_day,
                unit_value=item.unit_price,
                source="seed",
                occurred_at=utcnow() - timedelta(days=offset),
            )
        )
    db.commit()


def _link(db, vendor, supplier, *, shares=True, scope=("dairy",), status="active"):
    link = VendorDistributor(
        id=uuid.uuid4(),
        vendor_id=vendor.id,
        supplier_id=supplier.id,
        status=status,
        shares_demand=shares,
        scope_categories=list(scope),
    )
    db.add(link)
    db.commit()
    return link


def _listing(db, supplier, *, sku="Milk", category="dairy", unit="pkt", lead=None):
    entry = CatalogEntry(
        id=uuid.uuid4(),
        supplier_id=supplier.id,
        sku_name=sku,
        category=category,
        unit=unit,
        pack_size=12,
        pack_price=276,
        moq_packs=1,
        lead_days=lead,
    )
    db.add(entry)
    db.commit()
    return entry


def _consenting_book(db, supplier, count=4, *, per_day=10.0, qty=200):
    """`count` shops, all connected and all consenting to share dairy."""
    shops = []
    for i in range(count):
        v = _shop(db, f"Shop{i}", f"98765100{i:02d}")
        item = _stock(db, v, qty=qty)
        _sales(db, v, item, per_day=per_day)
        _link(db, v, supplier)
        shops.append((v, item))
    return shops


# ------------------------------------------------------- TC-D01 aggregation
def test_tc_d01_demand_aggregates_across_consenting_shops(db, supplier):
    _consenting_book(db, supplier, count=4)
    _listing(db, supplier)

    outlook = demand_outlook(db, supplier, horizon_days=7)

    assert outlook.consenting_shops == 4
    assert len(outlook.lines) == 1

    line = outlook.lines[0]
    assert line.sku_name == "Milk"
    assert line.shop_count == 4
    # Four shops selling ~10/day for a week is in the region of 280 packets
    # (adjusted for active festival lifts such as Ganesh Chaturthi / Janmashtami).
    assert 200 < line.expected_qty < 500
    # And the distributor is told how many crates that is, not just a number.
    assert line.packs_to_stock is not None and line.packs_to_stock > 0
    assert line.est_revenue > 0
    if line.expected_qty > 320:
        assert line.active_driver is not None


def test_tc_d01_demand_reports_festival_driver_during_lead_window():
    from app.services.distributor_intel import active_category_driver
    from datetime import date
    # Ganesh Chaturthi on 2026-09-14 with 7 lead days drives dairy
    driver = active_category_driver("dairy", date(2026, 9, 8), horizon_days=7)
    assert driver == "Ganesh Chaturthi"



def test_tc_d01_a_sku_the_distributor_does_not_sell_is_not_reported(db, supplier):
    """The outlook answers "what should I stock", not "what are they buying"."""
    _consenting_book(db, supplier, count=4)
    # No catalogue entry for Milk at all.

    outlook = demand_outlook(db, supplier, horizon_days=7)

    assert outlook.lines == []


# ------------------------------------------------------------ TC-D02 consent
def test_tc_d02_a_shop_that_withheld_consent_never_appears(db, supplier):
    """`shares_demand = False` means "order from you, but you do not see me"."""
    _consenting_book(db, supplier, count=3)

    private = _shop(db, "Private", "9876519999")
    item = _stock(db, private, qty=999)
    _sales(db, private, item, per_day=500)  # enormous, and must not show up
    _link(db, private, supplier, shares=False)
    _listing(db, supplier)

    outlook = demand_outlook(db, supplier, horizon_days=7)

    assert outlook.consenting_shops == 3
    assert outlook.total_connected == 4
    assert outlook.lines[0].shop_count == 3
    # If the private shop had leaked in, a 500/day seller would dominate.
    assert outlook.lines[0].expected_qty < 1000


def test_tc_d02_an_ended_connection_stops_sharing(db, supplier):
    _consenting_book(db, supplier, count=3)

    former = _shop(db, "Former", "9876518888")
    item = _stock(db, former, qty=999)
    _sales(db, former, item, per_day=400)
    _link(db, former, supplier, status="ended")
    _listing(db, supplier)

    outlook = demand_outlook(db, supplier, horizon_days=7)

    assert outlook.lines[0].shop_count == 3
    assert outlook.total_connected == 3


def test_tc_d02_out_of_scope_categories_are_invisible(db, supplier):
    """A grain wholesaler's connection does not admit dairy numbers."""
    for i in range(4):
        v = _shop(db, f"Grain{i}", f"98765200{i:02d}")
        item = _stock(db, v, sku="Atta", category="staples", qty=200, unit="kg")
        _sales(db, v, item, per_day=8)
        # Consent granted for staples only.
        _link(db, v, supplier, scope=("staples",))

        dairy = _stock(db, v, sku="Milk", category="dairy", qty=200)
        _sales(db, v, dairy, per_day=30)

    _listing(db, supplier, sku="Atta", category="staples", unit="kg")
    _listing(db, supplier, sku="Milk", category="dairy")

    outlook = demand_outlook(db, supplier, horizon_days=7)

    reported = {line.sku_name for line in outlook.lines}
    assert reported == {"Atta"}


def test_tc_d03_growing_the_catalogue_does_not_widen_a_frozen_scope(db, supplier):
    """The security property the whole consent design exists to provide.

    A wholesaler connected for staples cannot acquire visibility into dairy by
    adding dairy to their price list. Widening requires the shop to re-consent,
    which rewrites `scope_categories`.
    """
    for i in range(4):
        v = _shop(db, f"Shop{i}", f"98765300{i:02d}")
        atta = _stock(db, v, sku="Atta", category="staples", qty=200, unit="kg")
        _sales(db, v, atta, per_day=8)
        milk = _stock(db, v, sku="Milk", category="dairy", qty=200)
        _sales(db, v, milk, per_day=30)
        _link(db, v, supplier, scope=("staples",))

    _listing(db, supplier, sku="Atta", category="staples", unit="kg")

    before = {line.sku_name for line in demand_outlook(db, supplier).lines}
    assert before == {"Atta"}

    # The distributor now starts selling dairy too.
    _listing(db, supplier, sku="Milk", category="dairy")

    after = {line.sku_name for line in demand_outlook(db, supplier).lines}
    assert after == {"Atta"}, "adding a catalogue line must not widen consent"

    # Only the shop re-consenting opens it.
    for link in db.query(VendorDistributor).all():
        link.scope_categories = ["staples", "dairy"]
    db.commit()

    reconsented = {line.sku_name for line in demand_outlook(db, supplier).lines}
    assert reconsented == {"Atta", "Milk"}


def test_tc_d04_aggregates_below_the_k_threshold_are_suppressed(db, supplier):
    """Two shops' "total" is one shop's numbers wearing a disguise."""
    assert MIN_SHOPS_FOR_AGGREGATE == 3

    _consenting_book(db, supplier, count=2)
    _listing(db, supplier)

    outlook = demand_outlook(db, supplier, horizon_days=7)

    assert outlook.lines == []
    # The distributor still knows they have two shops — just not what they sell.
    assert outlook.total_connected == 2


# -------------------------------------------------------------- TC-D05 risk
def test_tc_d05_at_risk_finds_shops_that_run_out_before_the_van_arrives(db, supplier):
    """Two days of stock against a three-day lead time is a phone call."""
    shops = _consenting_book(db, supplier, count=3, per_day=10, qty=200)
    _listing(db, supplier, lead=3)

    # One shop is nearly empty: 20 packets left, selling 10 a day.
    starving, item = shops[0]
    item.current_qty = 20
    db.commit()

    at_risk = at_risk_shops(db, supplier)

    assert len(at_risk) == 1
    row = at_risk[0]
    assert row.vendor.id == starving.id
    assert row.lead_days == 3

    # The sales rate is a trailing 21-day mean over a window the fixture only
    # partly fills, so it lands just under 10/day rather than exactly on it.
    # Asserting a band rather than a point keeps this a test of the risk rule
    # instead of a test of the fixture's calendar.
    assert row.rate == pytest.approx(9.5, abs=0.6)
    assert row.cover == pytest.approx(2.1, abs=0.2)

    # Roughly three days of demand, less the 20 packets in hand.
    assert row.shortfall_by_arrival == pytest.approx(8.6, abs=1.5)
    # The suggestion covers that gap plus a week, rounded up to whole crates.
    assert row.suggested_packs >= 1
    assert row.est_value > 0


def test_tc_d05_a_well_stocked_shop_is_not_flagged(db, supplier):
    _consenting_book(db, supplier, count=3, per_day=10, qty=500)
    _listing(db, supplier, lead=1)

    assert at_risk_shops(db, supplier) == []


def test_tc_d05_at_risk_respects_consent_too(db, supplier):
    """The call list is the most tempting place to leak, so it is tested twice."""
    _consenting_book(db, supplier, count=3, per_day=10, qty=500)

    private = _shop(db, "Private", "9876517777")
    item = _stock(db, private, qty=5)
    _sales(db, private, item, per_day=20)
    _link(db, private, supplier, shares=False)
    _listing(db, supplier, lead=3)

    flagged = {row.vendor.id for row in at_risk_shops(db, supplier)}

    assert private.id not in flagged


def test_tc_d05_the_call_list_is_ordered_by_what_it_is_worth(db, supplier):
    shops = _consenting_book(db, supplier, count=3, per_day=10, qty=200)
    _listing(db, supplier, lead=3)

    small, small_item = shops[0]
    big, big_item = shops[1]
    small_item.current_qty = 20
    big_item.current_qty = 5
    db.commit()
    # The big shop sells much faster, so its gap is worth more.
    _sales(db, big, big_item, per_day=40, days=30)

    at_risk = at_risk_shops(db, supplier)

    assert at_risk[0].vendor.id == big.id
    assert at_risk[0].est_value >= at_risk[-1].est_value


# -------------------------------------------------------------- TC-D06 book
def test_tc_d06_the_book_reports_what_each_relationship_is_worth(
    db, vendor, supplier, milk_listing, connection, milk
):
    from app.services.ordering import amend_lines, apply_delivery, build_order, transition

    order = build_order(
        db,
        vendor=vendor,
        supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 4}],
    )
    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor")
    amend_lines(order, {}, "packs_delivered")
    apply_delivery(db, order)
    db.commit()

    rows = book_summary(db, supplier)

    assert len(rows) == 1
    row = rows[0]
    assert row.vendor.id == vendor.id
    assert row.order_count == 1
    assert row.delivered_count == 1
    assert row.revenue == pytest.approx(1104.0)  # 4 × 12 × ₹23
    assert row.outstanding == pytest.approx(1104.0)
    assert row.last_order_at is not None


def test_tc_d06_the_book_lists_shops_that_share_nothing(db, supplier):
    """A non-consenting shop is still a customer, and still appears here.

    Consent gates *demand* data, not the fact of the relationship or the money
    owed — those are the distributor's own records.
    """
    quiet = _shop(db, "Quiet", "9876516666")
    _link(db, quiet, supplier, shares=False)

    rows = book_summary(db, supplier)

    assert [r.vendor.id for r in rows] == [quiet.id]
    assert rows[0].connection.shares_demand is False


# --------------------------------------------------------- TC-D07 dead lines
def test_tc_d07_a_line_nobody_orders_is_surfaced(db, supplier):
    _listing(db, supplier, sku="Sabudana", category="staples", unit="kg")

    rows = dead_lines(db, supplier)

    assert len(rows) == 1
    assert rows[0].entry.sku_name == "Sabudana"
    assert rows[0].days_since_last_order is None


def test_tc_d07_a_recently_ordered_line_is_not_dead(
    db, vendor, supplier, milk_listing, connection
):
    from app.services.ordering import build_order, transition

    order = build_order(
        db,
        vendor=vendor,
        supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 1}],
    )
    transition(db, order, "placed", actor_role="vendor")
    db.commit()

    assert dead_lines(db, supplier) == []
