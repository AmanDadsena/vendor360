"""Identity, roles, and the consent a connection carries (TC-C**).

Two boundaries are under test here. One is that a token minted for a
wholesaler cannot read a shop's data, or the reverse. The other is that
consent, once given, means what it meant on the day it was given.
"""
from __future__ import annotations

import uuid

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.core.security import (
    ROLE_DISTRIBUTOR,
    ROLE_VENDOR,
    _require_role,
    create_access_token,
    decode_token,
)
from app.models import CatalogEntry, PurchaseOrder, Supplier, VendorDistributor
from app.services.connections import (
    ConnectionError_,
    catalog_categories,
    connect,
    disconnect,
)
from app.services.ordering import build_order, transition


# ------------------------------------------------------------ TC-C01 tokens
def test_tc_c01_a_token_carries_its_role(vendor):
    token = create_access_token(vendor.id, vendor.phone, ROLE_VENDOR)
    payload = decode_token(token)

    assert payload["role"] == ROLE_VENDOR
    assert payload["sub"] == str(vendor.id)


def test_tc_c01_a_distributor_token_is_refused_by_a_vendor_route(distributor_user):
    """The check runs before any query, so it cannot be forgotten downstream."""
    token = create_access_token(
        distributor_user.id, distributor_user.phone, ROLE_DISTRIBUTOR
    )
    payload = decode_token(token)

    with pytest.raises(HTTPException) as raised:
        _require_role(payload, ROLE_VENDOR)

    assert raised.value.status_code == 403
    assert "vendor" in raised.value.detail


def test_tc_c01_a_vendor_token_is_refused_by_a_distributor_route(vendor):
    token = create_access_token(vendor.id, vendor.phone, ROLE_VENDOR)
    payload = decode_token(token)

    with pytest.raises(HTTPException) as raised:
        _require_role(payload, ROLE_DISTRIBUTOR)

    assert raised.value.status_code == 403


def test_tc_c01_a_token_predating_the_role_claim_still_works_as_a_vendor():
    """Absence reads as vendor, which is what those tokens always were.

    It must never read as distributor: a missing claim cannot be allowed to
    satisfy the stronger check.
    """
    assert _require_role({}, ROLE_VENDOR) is None

    with pytest.raises(HTTPException):
        _require_role({}, ROLE_DISTRIBUTOR)


def test_tc_c01_a_tampered_token_does_not_decode(vendor):
    token = create_access_token(vendor.id, vendor.phone)
    forged = token[:-4] + "aaaa"

    with pytest.raises(HTTPException) as raised:
        decode_token(forged)

    assert raised.value.status_code == 401


# ------------------------------------------------------- TC-C02 connecting
def test_tc_c02_connecting_freezes_the_scope_as_it_stands(db, vendor, supplier):
    db.add_all(
        [
            CatalogEntry(
                supplier_id=supplier.id, sku_name="Atta",
                category="staples", unit="kg", pack_size=10, pack_price=420,
            ),
            CatalogEntry(
                supplier_id=supplier.id, sku_name="Rice",
                category="staples", unit="kg", pack_size=25, pack_price=1450,
            ),
        ]
    )
    db.commit()

    link = connect(db, vendor=vendor, supplier=supplier, credit_terms_days=7)
    db.commit()

    assert link.status == "active"
    assert link.scope_categories == ["staples"]
    assert link.credit_terms_days == 7
    assert link.covers("staples") is True
    assert link.covers("dairy") is False


def test_tc_c03_a_later_catalogue_line_does_not_widen_a_granted_scope(
    db, vendor, supplier
):
    """The security property the freeze exists to provide, at the source."""
    db.add(
        CatalogEntry(
            supplier_id=supplier.id, sku_name="Atta",
            category="staples", unit="kg", pack_size=10, pack_price=420,
        )
    )
    db.commit()

    link = connect(db, vendor=vendor, supplier=supplier)
    db.commit()
    assert link.covers("dairy") is False

    # The wholesaler starts selling dairy.
    db.add(
        CatalogEntry(
            supplier_id=supplier.id, sku_name="Milk",
            category="dairy", unit="pkt", pack_size=12, pack_price=276,
        )
    )
    db.commit()
    db.refresh(link)

    assert catalog_categories(db, supplier.id) == ["dairy", "staples"]
    assert link.scope_categories == ["staples"]
    assert link.covers("dairy") is False, "catalogue growth must not widen consent"


def test_tc_c03_re_consenting_is_what_widens_it(db, vendor, supplier):
    db.add(
        CatalogEntry(
            supplier_id=supplier.id, sku_name="Atta",
            category="staples", unit="kg", pack_size=10, pack_price=420,
        )
    )
    db.commit()
    connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    db.add(
        CatalogEntry(
            supplier_id=supplier.id, sku_name="Milk",
            category="dairy", unit="pkt", pack_size=12, pack_price=276,
        )
    )
    db.commit()

    link = connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    assert link.covers("dairy") is True


def test_tc_c02_withholding_demand_sharing_still_allows_trading(
    db, vendor, supplier, milk_listing
):
    """"Order from you, but you do not get to see what I am about to need."""
    link = connect(db, vendor=vendor, supplier=supplier, shares_demand=False)
    db.commit()

    assert link.status == "active"
    assert link.shares_demand is False
    # Scope is still recorded, so re-granting later needs no second decision.
    assert link.scope_categories == ["dairy"]
    assert link.covers("dairy") is False


def test_tc_c02_reconnecting_does_not_create_a_second_row(
    db, vendor, supplier, milk_listing
):
    connect(db, vendor=vendor, supplier=supplier, credit_terms_days=0)
    db.commit()
    connect(db, vendor=vendor, supplier=supplier, credit_terms_days=14)
    db.commit()

    links = db.scalars(
        select(VendorDistributor).where(VendorDistributor.vendor_id == vendor.id)
    ).all()

    assert len(links) == 1
    assert links[0].credit_terms_days == 14


# ---------------------------------------------------- TC-C04 disconnecting
def test_tc_c04_ending_a_relationship_keeps_the_record(
    db, vendor, supplier, milk_listing
):
    connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    link = disconnect(db, vendor=vendor, supplier_id=supplier.id)
    db.commit()

    assert link.status == "ended"
    assert link.shares_demand is False
    assert link.revoked_at is not None
    # The row survives so "who could see what, and when" stays answerable.
    assert link.connected_at is not None
    assert link.covers("dairy") is False


def test_tc_c04_an_open_order_blocks_the_break(
    db, vendor, supplier, milk_listing
):
    """Walking away from stock already on a van should not be a stray tap."""
    connect(db, vendor=vendor, supplier=supplier)
    order = build_order(
        db,
        vendor=vendor,
        supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
    )
    transition(db, order, "placed", actor_role="vendor")
    db.commit()

    with pytest.raises(ConnectionError_, match="still open"):
        disconnect(db, vendor=vendor, supplier_id=supplier.id)


def test_tc_c04_a_settled_order_does_not_block_it(
    db, vendor, supplier, milk_listing, milk
):
    connect(db, vendor=vendor, supplier=supplier)
    order = build_order(
        db,
        vendor=vendor,
        supplier=supplier,
        lines=[{"catalog_entry_id": milk_listing.id, "packs": 2}],
    )
    for status in ("placed", "confirmed", "dispatched", "delivered"):
        transition(db, order, status, actor_role="vendor")
    db.commit()

    link = disconnect(db, vendor=vendor, supplier_id=supplier.id)
    db.commit()

    assert link.status == "ended"


def test_tc_c04_disconnecting_a_stranger_is_an_error(db, vendor, supplier):
    with pytest.raises(ConnectionError_, match="not connected"):
        disconnect(db, vendor=vendor, supplier_id=supplier.id)


def test_tc_c05_an_empty_catalogue_grants_an_empty_scope(db, vendor, supplier):
    """Connecting to a wholesaler with no price list shares nothing yet."""
    link = connect(db, vendor=vendor, supplier=supplier)
    db.commit()

    assert link.scope_categories == []
    assert link.covers("dairy") is False
