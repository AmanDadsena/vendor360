"""The shortcuts that decide whether the app gets used (TC-E**).

Every one of these replaces something a shopkeeper or wholesaler would
otherwise do by hand — and each carries a rule about what it refuses to do
automatically, because a shortcut that guesses wrong costs more trust than it
saves taps.
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select

from app.models import CatalogEntry, PurchaseOrder
from app.services.connections import connect
from app.services.ordering import amend_lines, apply_delivery, build_order, transition


def _delivered_order(db, vendor, supplier, entry, *, packs=3):
    order = build_order(
        db,
        vendor=vendor,
        supplier=supplier,
        lines=[{"catalog_entry_id": entry.id, "packs": packs}],
    )
    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor")
    amend_lines(order, {}, "packs_delivered")
    apply_delivery(db, order)
    db.commit()
    return order


# ------------------------------------------------------- TC-E01 usual order
def test_tc_e01_rebuilds_the_last_delivered_basket(
    client_vendor, db, vendor, supplier, milk_listing
):
    connect(db, vendor=vendor, supplier=supplier)
    _delivered_order(db, vendor, supplier, milk_listing, packs=4)

    lines = client_vendor.get(f"/orders/usual/{supplier.id}").json()

    assert len(lines) == 1
    assert lines[0]["sku_name"] == "Milk"
    assert lines[0]["packs_ordered"] == 4


def test_tc_e01_reprices_from_todays_catalogue(
    client_vendor, db, vendor, supplier, milk_listing
):
    """Last month's price is a quote nobody honours."""
    connect(db, vendor=vendor, supplier=supplier)
    _delivered_order(db, vendor, supplier, milk_listing)

    milk_listing.pack_price = 360  # was 276
    db.commit()

    lines = client_vendor.get(f"/orders/usual/{supplier.id}").json()

    assert lines[0]["unit_price"] == pytest.approx(30.0)  # 360 / 12


def test_tc_e01_skips_a_line_the_wholesaler_has_withdrawn(
    client_vendor, db, vendor, supplier, milk_listing
):
    """Repeating it silently would produce an order they cannot fill."""
    connect(db, vendor=vendor, supplier=supplier)
    _delivered_order(db, vendor, supplier, milk_listing)

    milk_listing.active = False
    db.commit()

    assert client_vendor.get(f"/orders/usual/{supplier.id}").json() == []


def test_tc_e01_an_undelivered_order_is_not_a_usual(
    client_vendor, db, vendor, supplier, milk_listing
):
    """A draft or a cancelled order is not evidence of what they usually buy."""
    connect(db, vendor=vendor, supplier=supplier)
    order = build_order(
        db, vendor=vendor, supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
    )
    transition(db, order, "placed", actor_role="vendor")
    db.commit()

    assert client_vendor.get(f"/orders/usual/{supplier.id}").json() == []


def test_tc_e01_no_history_is_an_empty_list_not_an_error(
    client_vendor, db, vendor, supplier
):
    connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    response = client_vendor.get(f"/orders/usual/{supplier.id}")

    assert response.status_code == 200
    assert response.json() == []


# ------------------------------------------------------ TC-E02 bulk confirm
def test_tc_e02_accepts_every_waiting_order(
    client_dist, db, vendor, supplier, milk_listing
):
    connect(db, vendor=vendor, supplier=supplier)
    for _ in range(3):
        order = build_order(
            db, vendor=vendor, supplier=supplier,
            lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
        )
        transition(db, order, "placed", actor_role="vendor")
    db.commit()

    result = client_dist.post("/dist/orders/bulk-confirm").json()

    assert result["confirmed"] == 3
    assert result["failed"] == 0
    assert len(result["order_codes"]) == 3

    remaining = db.scalars(
        select(PurchaseOrder).where(PurchaseOrder.status == "placed")
    ).all()
    assert remaining == []


def test_tc_e02_leaves_orders_at_other_stages_alone(
    client_dist, db, vendor, supplier, milk_listing
):
    connect(db, vendor=vendor, supplier=supplier)
    dispatched = build_order(
        db, vendor=vendor, supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
    )
    for status in ("placed", "confirmed", "dispatched"):
        transition(db, dispatched, status, actor_role="vendor")
    db.commit()

    result = client_dist.post("/dist/orders/bulk-confirm").json()

    assert result["confirmed"] == 0
    db.refresh(dispatched)
    assert dispatched.status == "dispatched"


def test_tc_e02_confirms_in_full(client_dist, db, vendor, supplier, milk_listing):
    """A bulk action cannot make a part-fill decision, so it does not try."""
    connect(db, vendor=vendor, supplier=supplier)
    order = build_order(
        db, vendor=vendor, supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 5}],
    )
    transition(db, order, "placed", actor_role="vendor")
    db.commit()

    client_dist.post("/dist/orders/bulk-confirm")
    db.refresh(order)

    assert order.status == "confirmed"
    assert order.lines[0].packs_confirmed == 5


def test_tc_e02_nothing_waiting_is_not_an_error(client_dist):
    result = client_dist.post("/dist/orders/bulk-confirm").json()

    assert result == {"confirmed": 0, "failed": 0, "order_codes": []}


# ----------------------------------------------------------- TC-E03 dispatch
def test_tc_e03_groups_stops_by_locality(
    client_dist, db, vendor, supplier, milk_listing
):
    connect(db, vendor=vendor, supplier=supplier)
    order = build_order(
        db, vendor=vendor, supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
    )
    for status in ("placed", "confirmed"):
        transition(db, order, status, actor_role="vendor")
    db.commit()

    sheet = client_dist.get("/dist/dispatch").json()

    assert sheet["stop_count"] == 1
    assert len(sheet["legs"]) == 1
    leg = sheet["legs"][0]
    assert leg["locality"] == vendor.locality
    assert leg["stops"][0]["store_name"] == vendor.store_name
    assert leg["stops"][0]["order_code"] == order.code


def test_tc_e03_carries_what_to_collect_at_the_door(
    client_dist, db, vendor, supplier, milk_listing
):
    """A driver who does not know what to ask for does not ask."""
    connect(db, vendor=vendor, supplier=supplier)
    order = build_order(
        db, vendor=vendor, supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 4}],
    )
    for status in ("placed", "confirmed"):
        transition(db, order, status, actor_role="vendor")
    db.commit()

    sheet = client_dist.get("/dist/dispatch").json()

    assert sheet["to_collect"] == pytest.approx(order.amount_total)
    assert sheet["legs"][0]["stops"][0]["amount_due"] == pytest.approx(
        order.amount_total
    )


def test_tc_e03_a_settled_or_undelivered_order_is_not_a_stop(
    client_dist, db, vendor, supplier, milk_listing, milk
):
    connect(db, vendor=vendor, supplier=supplier)

    # Still a draft — the shop has not sent it.
    build_order(
        db, vendor=vendor, supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 1}],
    )
    # Already delivered.
    _delivered_order(db, vendor, supplier, milk_listing)
    db.commit()

    assert client_dist.get("/dist/dispatch").json()["stop_count"] == 0


def test_tc_e03_an_empty_round_is_an_empty_sheet(client_dist):
    sheet = client_dist.get("/dist/dispatch").json()

    assert sheet["stop_count"] == 0
    assert sheet["legs"] == []
    assert sheet["to_collect"] == 0


def test_wastage_summary_reports_losses_and_prevention_tips(
    client_vendor, db, vendor, milk
):
    from app.core.db import utcnow
    from app.models import Transaction

    db.add(
        Transaction(
            vendor_id=vendor.id,
            item_id=milk.id,
            type="wastage",
            qty=4.0,
            unit_value=30.0,
            source="manual",
            occurred_at=utcnow(),
        )
    )
    db.commit()

    res = client_vendor.get("/inventory/wastage/summary")
    assert res.status_code == 200
    data = res.json()
    assert data["total_lost_value"] == 120.0
    assert data["total_lost_units"] == 4.0
    assert data["wastage_events_count"] == 1
    assert data["top_spoilage_category"] == "dairy"
    assert "dairy" in data["recovery_tip"]

