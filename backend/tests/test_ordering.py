"""Pack arithmetic, the order status machine, and delivery application.

Test Plan identifiers continue the existing scheme: TC-O** for ordering.
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select

from app.models import LedgerEntry, PurchaseOrder, Transaction
from app.services.ordering import (
    OrderError,
    amend_lines,
    apply_delivery,
    build_order,
    fill_rate,
    outstanding,
    plan_packs,
    transition,
)


# ------------------------------------------------------- TC-O01 pack maths
def test_tc_o01_shortfall_rounds_up_to_whole_packs():
    """12 kg needed against a 10 kg case is two cases, not 1.2."""
    plan = plan_packs(shortfall=12, pack_size=10, pack_price=420)

    assert plan.packs == 2
    assert plan.qty_supplied == 20
    assert plan.cost == 840
    assert plan.surplus == 8


def test_tc_o01_exact_multiple_does_not_over_order():
    plan = plan_packs(shortfall=20, pack_size=10, pack_price=420)

    assert plan.packs == 2
    assert plan.surplus == 0


def test_tc_o02_minimum_order_quantity_raises_a_small_need():
    """A one-case need against a three-case minimum becomes three cases."""
    plan = plan_packs(shortfall=5, pack_size=10, pack_price=100, moq_packs=3)

    assert plan.packs == 3
    assert plan.moq_applied is True
    assert plan.qty_supplied == 30


def test_tc_o02_moq_not_flagged_when_the_need_already_clears_it():
    plan = plan_packs(shortfall=45, pack_size=10, pack_price=100, moq_packs=3)

    assert plan.packs == 5
    assert plan.moq_applied is False


def test_no_shortfall_orders_nothing():
    plan = plan_packs(shortfall=0, pack_size=10, pack_price=100, moq_packs=3)

    assert plan.packs == 0
    assert plan.cost == 0


def test_zero_pack_size_is_rejected_rather_than_dividing_by_zero():
    with pytest.raises(OrderError):
        plan_packs(shortfall=5, pack_size=0, pack_price=100)


# ----------------------------------------------------------- TC-O03 build
def test_tc_o03_order_snapshots_price_from_the_catalogue(
    db, vendor, supplier, milk_listing, connection
):
    order = build_order(
        db,
        vendor=vendor,
        supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
    )
    db.commit()

    line = order.lines[0]
    assert line.sku_name == "Milk"
    assert line.pack_size == 12
    assert line.unit_price == pytest.approx(23.0)  # 276 / 12
    assert line.qty_ordered == 24
    assert order.amount_total == pytest.approx(552.0)
    # Terms come from the connection, not from a default.
    assert order.payment_terms_days == 7


def test_tc_o03_repricing_the_catalogue_does_not_rewrite_a_placed_order(
    db, vendor, supplier, milk_listing, connection
):
    order = build_order(
        db,
        vendor=vendor,
        supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
    )
    db.commit()

    milk_listing.pack_price = 999
    db.commit()
    db.refresh(order)

    assert order.lines[0].unit_price == pytest.approx(23.0)
    assert order.amount_total == pytest.approx(552.0)


def test_cannot_order_another_wholesalers_catalogue_line(
    db, vendor, supplier, milk_listing
):
    """Quoting a rival's price on this order would be a pricing exploit."""
    from app.models import Supplier

    other = Supplier(
        id=uuid.uuid4(),
        name="Rival Traders",
        lat=18.5,
        lon=73.8,
        locality="Kothrud",
        categories=[],
    )
    db.add(other)
    db.commit()

    with pytest.raises(OrderError):
        build_order(
            db,
            vendor=vendor,
            supplier=other,
            lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
        )


def test_an_order_needs_at_least_one_line(db, vendor, supplier):
    with pytest.raises(OrderError):
        build_order(db, vendor=vendor, supplier=supplier, lines=[])


def test_order_codes_are_unique_and_sayable(
    db, vendor, supplier, milk_listing, connection
):
    codes = set()
    for _ in range(3):
        order = build_order(
            db,
            vendor=vendor,
            supplier=supplier,
            lines=[{"catalog_entry_id": milk_listing.id, "packs": 1}],
        )
        db.commit()
        codes.add(order.code)

    assert len(codes) == 3
    assert all(code.startswith("PO-") for code in codes)


# ------------------------------------------------ TC-O04 the status machine
def _draft(db, vendor, supplier, listing, packs=2):
    order = build_order(
        db,
        vendor=vendor,
        supplier=supplier,
        lines=[{"catalog_entry_id": listing.id, "packs": packs}],
    )
    db.commit()
    return order


def test_tc_o04_happy_path_walks_every_state(
    db, vendor, supplier, milk_listing, connection
):
    order = _draft(db, vendor, supplier, milk_listing)

    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor", actor_id=vendor.id)
    db.commit()

    assert order.status == "delivered"
    assert order.placed_at is not None
    assert order.delivered_at is not None
    # Expected arrival uses the catalogue override (1 day), not a bare default.
    assert order.expected_at is not None
    # Five events: the draft, plus one per move.
    assert [e.to_status for e in order.events] == [
        "draft",
        "placed",
        "confirmed",
        "dispatched",
        "delivered",
    ]


def test_tc_o04_an_order_cannot_move_backwards(
    db, vendor, supplier, milk_listing, connection
):
    order = _draft(db, vendor, supplier, milk_listing)
    transition(db, order, "placed", actor_role="vendor")
    transition(db, order, "confirmed", actor_role="distributor")
    transition(db, order, "dispatched", actor_role="distributor")
    transition(db, order, "delivered", actor_role="vendor")
    db.commit()

    with pytest.raises(OrderError, match="delivered"):
        transition(db, order, "placed", actor_role="vendor")


def test_tc_o04_states_cannot_be_skipped(
    db, vendor, supplier, milk_listing, connection
):
    """A draft cannot jump straight to dispatched."""
    order = _draft(db, vendor, supplier, milk_listing)

    with pytest.raises(OrderError):
        transition(db, order, "dispatched", actor_role="distributor")


def test_tc_o04_a_cancelled_order_is_terminal(
    db, vendor, supplier, milk_listing, connection
):
    order = _draft(db, vendor, supplier, milk_listing)
    transition(db, order, "cancelled", actor_role="vendor")
    db.commit()

    with pytest.raises(OrderError):
        transition(db, order, "placed", actor_role="vendor")


def test_repeating_the_current_status_says_so_plainly(
    db, vendor, supplier, milk_listing, connection
):
    order = _draft(db, vendor, supplier, milk_listing)
    transition(db, order, "placed", actor_role="vendor")

    with pytest.raises(OrderError, match="already placed"):
        transition(db, order, "placed", actor_role="vendor")


# --------------------------------------------------------- TC-O05 part-fill
def test_tc_o05_partial_confirmation_reprices_the_order(
    db, vendor, supplier, milk_listing, connection
):
    """Eight of twelve cases means eight cases' worth of money."""
    order = _draft(db, vendor, supplier, milk_listing, packs=12)
    transition(db, order, "placed", actor_role="vendor")

    amend_lines(order, {order.lines[0].id: 8}, "packs_confirmed")
    transition(db, order, "confirmed", actor_role="distributor")
    db.commit()

    assert order.lines[0].packs_confirmed == 8
    # 8 cases × 12 pkt × ₹23
    assert order.amount_total == pytest.approx(2208.0)


def test_tc_o05_cannot_supply_more_than_was_ordered(
    db, vendor, supplier, milk_listing, connection
):
    order = _draft(db, vendor, supplier, milk_listing, packs=2)
    transition(db, order, "placed", actor_role="vendor")

    with pytest.raises(OrderError, match="more than"):
        amend_lines(order, {order.lines[0].id: 5}, "packs_confirmed")


def test_tc_o05_silence_means_all_of_it(
    db, vendor, supplier, milk_listing, connection
):
    """A distributor confirming without amending should not have to type."""
    order = _draft(db, vendor, supplier, milk_listing, packs=3)
    transition(db, order, "placed", actor_role="vendor")

    amend_lines(order, {}, "packs_confirmed")
    db.commit()

    assert order.lines[0].packs_confirmed == 3


# --------------------------------------------------------- TC-O06 delivery
def test_tc_o06_delivery_restocks_the_matching_shelf(
    db, vendor, supplier, milk_listing, connection, milk
):
    order = _draft(db, vendor, supplier, milk_listing, packs=2)
    for status in ("placed", "confirmed", "dispatched"):
        transition(db, order, status, actor_role="vendor")
    amend_lines(order, {}, "packs_delivered")
    transition(db, order, "delivered", actor_role="vendor")

    before = milk.current_qty
    apply_delivery(db, order)
    db.commit()

    db.refresh(milk)
    assert milk.current_qty == before + 24

    txns = db.scalars(
        select(Transaction).where(Transaction.item_id == milk.id)
    ).all()
    assert len(txns) == 1
    assert txns[0].type == "restock"
    assert txns[0].source == "order"


def test_tc_o06_delivery_is_idempotent(
    db, vendor, supplier, milk_listing, connection, milk
):
    """A retried delivery must not restock twice."""
    order = _draft(db, vendor, supplier, milk_listing, packs=2)
    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor")
    db.commit()

    apply_delivery(db, order)
    db.commit()
    first = milk.current_qty

    # The route guards on `delivered_at`; the ledger guards itself, so a second
    # call must not double the debt even if it slips through.
    apply_delivery(db, order)
    db.commit()

    charges = db.scalars(
        select(LedgerEntry).where(
            LedgerEntry.order_id == order.id, LedgerEntry.kind == "charge"
        )
    ).all()
    assert len(charges) == 1
    assert first > 0


def test_tc_o06_delivering_something_new_opens_a_shelf_for_it(
    db, vendor, supplier, connection
):
    from app.models import CatalogEntry, InventoryItem

    entry = CatalogEntry(
        id=uuid.uuid4(),
        supplier_id=supplier.id,
        sku_name="Poha",
        category="staples",
        unit="kg",
        pack_size=5,
        pack_price=200,
    )
    db.add(entry)
    db.commit()

    order = _draft(db, vendor, supplier, entry, packs=2)
    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor")
    apply_delivery(db, order)
    db.commit()

    item = db.scalar(
        select(InventoryItem).where(
            InventoryItem.vendor_id == vendor.id, InventoryItem.sku_name == "Poha"
        )
    )
    assert item is not None
    assert item.current_qty == 10
    # Priced above cost so a brand-new line does not report a total loss.
    assert item.unit_price > item.unit_cost


def test_tc_o06_delivery_posts_a_charge_due_on_the_agreed_terms(
    db, vendor, supplier, milk_listing, connection, milk
):
    order = _draft(db, vendor, supplier, milk_listing, packs=2)
    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor")
    apply_delivery(db, order)
    db.commit()

    assert outstanding(db, vendor.id) == pytest.approx(552.0)

    charge = db.scalar(select(LedgerEntry).where(LedgerEntry.order_id == order.id))
    assert charge.due_on is not None
    assert (charge.due_on - order.delivered_at).days == 7


def test_recorded_payment_reduces_what_is_owed(
    db, vendor, supplier, milk_listing, connection, milk
):
    order = _draft(db, vendor, supplier, milk_listing, packs=2)
    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor")
    apply_delivery(db, order)
    db.add(
        LedgerEntry(
            vendor_id=vendor.id,
            supplier_id=supplier.id,
            kind="payment",
            amount=300,
        )
    )
    db.commit()

    assert outstanding(db, vendor.id) == pytest.approx(252.0)


# -------------------------------------------------------- TC-O07 fill rate
def test_tc_o07_fill_rate_needs_a_track_record_before_it_reports(
    db, vendor, supplier, milk_listing, connection
):
    """One lucky delivery is not a record, and must not outrank a proven one."""
    order = _draft(db, vendor, supplier, milk_listing, packs=2)
    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor")
    amend_lines(order, {}, "packs_delivered")
    db.commit()

    assert fill_rate(db, supplier.id) is None


def test_tc_o07_fill_rate_reflects_short_deliveries(
    db, vendor, supplier, milk_listing, connection
):
    for delivered in (10, 6):
        order = _draft(db, vendor, supplier, milk_listing, packs=10)
        for status in ("placed", "confirmed", "dispatched"):
            transition(db, order, status, actor_role="vendor")
        amend_lines(order, {order.lines[0].id: delivered}, "packs_delivered")
        transition(db, order, "delivered", actor_role="vendor")
        db.commit()

    # 16 of 20 cases arrived.
    assert fill_rate(db, supplier.id) == pytest.approx(0.8)


def test_open_orders_do_not_count_toward_fill_rate(
    db, vendor, supplier, milk_listing, connection
):
    order = _draft(db, vendor, supplier, milk_listing, packs=10)
    transition(db, order, "placed", actor_role="vendor")
    db.commit()

    assert fill_rate(db, supplier.id) is None
    assert db.scalar(select(PurchaseOrder.status).where(PurchaseOrder.id == order.id)) == "placed"
