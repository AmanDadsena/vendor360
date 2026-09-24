"""The customer credit book (TC-U**).

The rules worth testing are the ones a shopkeeper would argue about at the
counter: what is owed, how old it is, and what a part-payment settles.
"""
from __future__ import annotations

import uuid
from datetime import timedelta

import pytest
from sqlalchemy import select

from app.core.db import utcnow
from app.models import Customer, UdhaarEntry, Vendor
from app.services import udhaar


@pytest.fixture()
def customer(db, vendor):
    c = Customer(vendor_id=vendor.id, name="Suresh", phone="9876500099")
    db.add(c)
    db.commit()
    return c


def days_ago(n: int):
    return utcnow() - timedelta(days=n)


# ------------------------------------------------------------- TC-U01 shape
def test_tc_u01_an_entry_belongs_to_a_customer_and_a_shop(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 320)
    db.commit()

    entry = db.scalar(select(UdhaarEntry))
    assert entry.customer_id == customer.id
    assert entry.vendor_id == vendor.id
    assert entry.kind == "credit"
    assert entry.amount == 320


# ---------------------------------------------------------- TC-U02 balances
def test_tc_u02_balance_is_credits_minus_payments(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 500)
    udhaar.record(db, vendor, customer, "payment", 200)

    assert udhaar.statement(db, vendor, customer).owed == 300


def test_tc_u02_a_settled_customer_leaves_the_book(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 100)
    udhaar.record(db, vendor, customer, "payment", 100)

    assert udhaar.balances(db, vendor) == []
    assert udhaar.totals(db, vendor).outstanding == 0


def test_tc_u02_overpayment_is_not_a_negative_debt(db, vendor, customer):
    """A shop holding credit for a customer does not owe them money."""
    udhaar.record(db, vendor, customer, "credit", 100)
    udhaar.record(db, vendor, customer, "payment", 150)

    assert udhaar.statement(db, vendor, customer).owed == 0


# ------------------------------------------------------- TC-U03 settlement
def test_tc_u03_a_payment_settles_the_oldest_debt_first(db, vendor, customer):
    """The same rule the distributor ledger uses.

    Applying a payment to the newest charge instead would leave the oldest one
    standing while the *reported* age fell, which is the flattering answer and
    the wrong one.
    """
    udhaar.record(db, vendor, customer, "credit", 100, occurred_at=days_ago(40))
    udhaar.record(db, vendor, customer, "credit", 100, occurred_at=days_ago(2))
    udhaar.record(db, vendor, customer, "payment", 100)

    balance = udhaar.balances(db, vendor)[0]
    assert balance.owed == 100
    # The forty-day-old charge is gone; what stands is two days old.
    assert balance.days_outstanding <= 3
    assert balance.is_stale is False


def test_tc_u03_a_part_payment_leaves_the_oldest_charge_ageing(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 300, occurred_at=days_ago(45))
    udhaar.record(db, vendor, customer, "payment", 100)

    balance = udhaar.balances(db, vendor)[0]
    assert balance.owed == 200
    assert balance.days_outstanding >= 44
    assert balance.is_stale is True


# ------------------------------------------------------------ TC-U04 order
def test_tc_u04_the_book_lists_the_oldest_debt_first(db, vendor):
    recent = Customer(vendor_id=vendor.id, name="Recent")
    ancient = Customer(vendor_id=vendor.id, name="Ancient")
    db.add_all([recent, ancient])
    db.flush()

    udhaar.record(db, vendor, recent, "credit", 5000, occurred_at=days_ago(1))
    udhaar.record(db, vendor, ancient, "credit", 200, occurred_at=days_ago(90))
    db.commit()

    names = [b.customer.name for b in udhaar.balances(db, vendor)]
    # Oldest first, not largest: a ninety-day-old ₹200 is the one to chase.
    assert names == ["Ancient", "Recent"]


# ----------------------------------------------------------- TC-U05 guards
def test_tc_u05_amounts_must_be_positive(db, vendor, customer):
    with pytest.raises(ValueError):
        udhaar.record(db, vendor, customer, "credit", -1)
    with pytest.raises(ValueError):
        udhaar.record(db, vendor, customer, "payment", 0)


def test_tc_u05_an_unknown_kind_is_refused(db, vendor, customer):
    with pytest.raises(ValueError):
        udhaar.record(db, vendor, customer, "discount", 50)


def test_tc_u05_a_customer_belongs_to_one_shop(db, vendor, customer):
    other = Vendor(
        id=uuid.uuid4(),
        name="Other",
        store_name="Other Stores",
        phone="9000000001",
    )
    db.add(other)
    db.flush()

    with pytest.raises(ValueError):
        udhaar.record(db, other, customer, "credit", 100)


# --------------------------------------------------------- TC-U06 statement
def test_tc_u06_a_statement_reads_newest_first(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 100, occurred_at=days_ago(5))
    udhaar.record(db, vendor, customer, "payment", 40, occurred_at=days_ago(1))

    entries = udhaar.statement(db, vendor, customer).entries
    assert [e.kind for e in entries] == ["payment", "credit"]


def test_tc_u06_totals_report_the_whole_book(db, vendor):
    a = Customer(vendor_id=vendor.id, name="A")
    b = Customer(vendor_id=vendor.id, name="B")
    db.add_all([a, b])
    db.flush()
    udhaar.record(db, vendor, a, "credit", 320, occurred_at=days_ago(50))
    udhaar.record(db, vendor, b, "credit", 180, occurred_at=days_ago(3))
    db.commit()

    totals = udhaar.totals(db, vendor)
    assert totals.outstanding == 500
    assert totals.customers == 2
    assert totals.oldest_days >= 49


# ------------------------------------------------------- TC-U07 day window
def test_tc_u07_day_movement_counts_only_that_day(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 500, occurred_at=days_ago(2))
    udhaar.record(db, vendor, customer, "credit", 120)
    udhaar.record(db, vendor, customer, "payment", 300)
    db.commit()

    start = utcnow() - timedelta(hours=12)
    end = utcnow() + timedelta(hours=12)
    given, collected = udhaar.day_movement(db, vendor, start, end)

    assert given == 120
    assert collected == 300
