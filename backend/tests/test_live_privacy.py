"""Who a live event may reach (TC-LP**).

The consent model exists so a grain wholesaler cannot see a shop's milk
numbers. A push channel that skipped the check would hand a distributor in real
time exactly what the pull path spends effort withholding — and it would do it
invisibly, because nothing on screen says who else received an event.

So these mirror `test_distributor_intel.py`'s privacy cases against the
audience computation instead of the aggregate.
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select

from app.models import Alert, CatalogEntry, Supplier, VendorDistributor
from app.services.audiences import (
    anonymous,
    for_locality_surge,
    for_order,
    for_vendor_activity,
)
from app.services.connections import connect
from app.services.detectors import Detection
from app.services.event_bus import Audience, DomainEvent, EventBus, Subscriber
from app.services.notifier import notify


def _listing(db, supplier, *, sku="Milk", category="dairy"):
    entry = CatalogEntry(
        supplier_id=supplier.id, sku_name=sku, category=category,
        unit="pkt", pack_size=12, pack_price=276, moq_packs=1,
    )
    db.add(entry)
    db.commit()
    return entry


def _other_supplier(db, name="Grain Only", category="staples"):
    supplier = Supplier(
        id=uuid.uuid4(), name=name, kind="distributor", lat=18.5, lon=73.8,
        locality="Camp", city="Pune", categories=[category], lead_days=2,
        min_order_value=0, rating=4.0,
    )
    db.add(supplier)
    db.commit()
    _listing(db, supplier, sku="Atta", category=category)
    return supplier


# ------------------------------------------------------- TC-LP01 entitlement
def test_tc_lp01_a_consenting_distributor_is_in_the_audience(
    db, vendor, supplier, milk_listing
):
    connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    audience = for_vendor_activity(db, vendor_id=vendor.id, category="dairy")

    assert vendor.id in audience.vendor_ids
    assert supplier.id in audience.supplier_ids


def test_tc_lp01_the_shop_is_always_in_its_own_audience(db, vendor, supplier):
    """Even with no connections at all, a shop hears about its own stock."""
    audience = for_vendor_activity(db, vendor_id=vendor.id, category="dairy")

    assert audience.vendor_ids == frozenset({vendor.id})
    assert audience.supplier_ids == frozenset()


def test_tc_lp02_withholding_consent_keeps_the_distributor_out(
    db, vendor, supplier, milk_listing
):
    """"Order from you, but you do not see me" must hold on the live channel too."""
    connect(db, vendor=vendor, supplier=supplier, shares_demand=False)
    db.commit()

    audience = for_vendor_activity(db, vendor_id=vendor.id, category="dairy")

    assert vendor.id in audience.vendor_ids
    assert supplier.id not in audience.supplier_ids


def test_tc_lp02_an_ended_connection_hears_nothing(
    db, vendor, supplier, milk_listing
):
    link = connect(db, vendor=vendor, supplier=supplier)
    link.status = "ended"
    db.commit()

    audience = for_vendor_activity(db, vendor_id=vendor.id, category="dairy")

    assert supplier.id not in audience.supplier_ids


def test_tc_lp03_frozen_scope_gates_the_category(db, vendor, supplier):
    """A grain wholesaler learns nothing when the shop runs out of milk."""
    _listing(db, supplier, sku="Atta", category="staples")
    connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    staples = for_vendor_activity(db, vendor_id=vendor.id, category="staples")
    dairy = for_vendor_activity(db, vendor_id=vendor.id, category="dairy")

    assert supplier.id in staples.supplier_ids
    assert supplier.id not in dairy.supplier_ids


def test_tc_lp03_catalogue_growth_does_not_widen_the_live_audience(
    db, vendor, supplier
):
    """The regression the frozen scope exists to prevent, on the push path."""
    _listing(db, supplier, sku="Atta", category="staples")
    connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    assert supplier.id not in for_vendor_activity(
        db, vendor_id=vendor.id, category="dairy"
    ).supplier_ids

    # The wholesaler starts selling dairy tomorrow.
    _listing(db, supplier, sku="Milk", category="dairy")

    assert supplier.id not in for_vendor_activity(
        db, vendor_id=vendor.id, category="dairy"
    ).supplier_ids, "adding a catalogue line must not widen a live audience"


# ------------------------------------------------------------ TC-LP04 alerts
def test_tc_lp04_no_alert_row_is_written_for_an_unentitled_distributor(
    db, vendor, supplier, milk, milk_listing
):
    """Not merely unsubscribed — no record exists for them to read later.

    Filtering only the socket would leave the alert sitting in the table for
    the pull path to serve up, which is the same leak arriving more slowly.
    """
    outsider = _other_supplier(db)
    connect(db, vendor=vendor, supplier=outsider)  # staples only
    db.commit()

    notify(
        db,
        Detection(
            kind="stockout", severity="warning",
            title="Milk is running low", body="Down to 2 pkt.",
            payload={"sku_name": "Milk"},
        ),
        vendor=vendor,
        category="dairy",
        subject_id=milk.id,
    )
    db.commit()

    rows = db.scalars(select(Alert)).all()

    assert len(rows) == 1
    assert rows[0].vendor_id == vendor.id
    assert rows[0].supplier_id is None


def test_tc_lp04_a_consenting_distributor_gets_their_own_wording(
    db, vendor, supplier, milk, milk_listing
):
    connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    notify(
        db,
        Detection(
            kind="stockout", severity="urgent",
            title="Milk is finished", body="Down to 0 pkt.",
            payload={"sku_name": "Milk"},
        ),
        vendor=vendor,
        category="dairy",
        subject_id=milk.id,
    )
    db.commit()

    shop = db.scalar(select(Alert).where(Alert.vendor_id == vendor.id))
    dist = db.scalar(select(Alert).where(Alert.supplier_id == supplier.id))

    assert shop is not None and dist is not None
    # The shop's copy is about their shelf; the wholesaler's is about a customer.
    assert vendor.store_name in dist.title
    assert vendor.store_name not in shop.title
    # And it does not buzz them: it is someone else's shelf.
    assert shop.severity == "urgent"
    assert dist.severity == "info"


# --------------------------------------------------------------- TC-LP05 bus
def test_tc_lp05_the_bus_delivers_only_to_entitled_subscribers(db):
    bus = EventBus()
    mine, theirs = uuid.uuid4(), uuid.uuid4()

    a = bus.subscribe(Subscriber(vendor_id=mine))
    b = bus.subscribe(Subscriber(vendor_id=theirs))

    delivered = bus.publish(
        DomainEvent(kind="stockout", audience=Audience.just_vendor(mine))
    )

    assert delivered == 1
    assert a.queue.qsize() == 1
    assert b.queue.qsize() == 0


def test_tc_lp05_an_anonymous_event_reaches_everyone(db):
    bus = EventBus()
    a = bus.subscribe(Subscriber(vendor_id=uuid.uuid4()))
    b = bus.subscribe(Subscriber(supplier_id=uuid.uuid4()))

    delivered = bus.publish(DomainEvent(kind="heatmap", audience=anonymous()))

    assert delivered == 2
    assert a.queue.qsize() == 1 and b.queue.qsize() == 1


def test_tc_lp05_a_subscriber_that_stops_reading_is_dropped(db):
    """A crashed tab must not hold a subscription for the process lifetime."""
    from app.services.event_bus import MAX_QUEUED_EVENTS

    bus = EventBus()
    stuck = bus.subscribe(Subscriber(vendor_id=uuid.uuid4()))
    event = DomainEvent(kind="heatmap", audience=anonymous())

    for _ in range(MAX_QUEUED_EVENTS):
        bus.publish(event)

    assert bus.size == 1
    assert bus.publish(event) == 0
    assert bus.size == 0, "an overflowing subscriber is unsubscribed"
    assert stuck.dropped is True


def test_tc_lp05_the_wire_shape_never_carries_the_audience(db):
    """Who else received an event is not the recipient's business."""
    event = DomainEvent(
        kind="stockout",
        audience=Audience.of(vendors=[uuid.uuid4()], suppliers=[uuid.uuid4()]),
        payload={"sku_name": "Milk"},
    )

    wire = event.wire()

    assert wire["type"] == "stockout"
    assert wire["sku_name"] == "Milk"
    assert "audience" not in wire
    assert "vendor_ids" not in wire
    assert "supplier_ids" not in wire


# ------------------------------------------------------------- TC-LP06 order
def test_tc_lp06_an_order_reaches_both_sides_without_a_consent_check(db):
    """A wholesaler is entitled to the order placed with them, whatever else
    the shop withholds."""
    v, s = uuid.uuid4(), uuid.uuid4()

    audience = for_order(vendor_id=v, supplier_id=s)

    assert audience.admits(vendor_id=v)
    assert audience.admits(supplier_id=s)
    assert not audience.admits(vendor_id=uuid.uuid4())


# ------------------------------------------------------------- TC-LP07 surge
def test_tc_lp07_a_surge_does_not_leak_a_non_consenting_participant(
    db, vendor, supplier, milk_listing
):
    """A shop can be in a pool without its distributors being told it is short."""
    connect(db, vendor=vendor, supplier=supplier, shares_demand=False)
    db.commit()

    audience = for_locality_surge(
        db, vendor_ids={vendor.id}, category="dairy"
    )

    assert vendor.id in audience.vendor_ids
    assert supplier.id not in audience.supplier_ids
