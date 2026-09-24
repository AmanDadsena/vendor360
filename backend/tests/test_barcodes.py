"""Scanning a pack (TC-B01..B06).

A barcode is a global product identifier, not a shop's private data, so the
lookup answers two different questions with one endpoint: "what is this, and
do I already stock it?" The first question is answerable from anyone's
catalogue; the second only from the scanning vendor's own shelf.
"""
from __future__ import annotations

import uuid

from app.models import CatalogEntry, InventoryItem, Vendor


def test_tc_b01_a_scanned_code_finds_the_item_on_the_shelf(
    client_vendor, db, milk
):
    milk.barcode = "8901234567894"
    db.commit()

    r = client_vendor.get("/inventory/by-barcode/8901234567894")

    assert r.status_code == 200
    body = r.json()
    assert body["sku_name"] == "Milk"
    assert body["item"] is not None
    assert body["item"]["id"] == str(milk.id)
    assert body["item"]["current_qty"] == 50


def test_tc_b02_an_unknown_code_is_a_404(client_vendor):
    r = client_vendor.get("/inventory/by-barcode/8999999999990")
    assert r.status_code == 404


def test_tc_b03_another_shops_barcode_is_invisible(client_vendor, db, vendor):
    other = Vendor(
        id=uuid.uuid4(),
        name="Someone Else",
        store_name="Other Stores",
        phone="9876500099",
        lat=18.5,
        lon=73.8,
    )
    db.add(other)
    db.flush()
    db.add(
        InventoryItem(
            id=uuid.uuid4(),
            vendor_id=other.id,
            sku_name="Their Atta",
            category="staples",
            barcode="8901111111116",
            current_qty=9,
        )
    )
    db.commit()

    r = client_vendor.get("/inventory/by-barcode/8901111111116")

    # Not 403: confirming the code exists somewhere would leak the fact that
    # another shop stocks it.
    assert r.status_code == 404


def test_tc_b04_a_code_arrives_with_whatever_the_scanner_adds(
    client_vendor, db, milk
):
    milk.barcode = "8901234567894"
    db.commit()

    # Hardware scanners and hand-typed codes both bring punctuation along.
    r = client_vendor.get("/inventory/by-barcode/890-1234 567894%0A")

    assert r.status_code == 200
    assert r.json()["item"]["id"] == str(milk.id)


def test_tc_b05_the_catalogue_names_a_pack_the_shop_does_not_stock(
    client_vendor, db, supplier
):
    db.add(
        CatalogEntry(
            id=uuid.uuid4(),
            supplier_id=supplier.id,
            sku_name="Parle-G 800g",
            category="snacks",
            unit="pkt",
            barcode="8901719101014",
            pack_size=12,
            pack_price=960,
        )
    )
    db.commit()

    r = client_vendor.get("/inventory/by-barcode/8901719101014")

    assert r.status_code == 200
    body = r.json()
    # Enough to open the add-item form with the fields already filled.
    assert body["sku_name"] == "Parle-G 800g"
    assert body["category"] == "snacks"
    assert body["unit"] == "pkt"
    # Not on this shelf yet — the scan screen offers to add it.
    assert body["item"] is None


def test_tc_b06_the_catalogue_answer_carries_no_price(
    client_vendor, db, supplier
):
    db.add(
        CatalogEntry(
            id=uuid.uuid4(),
            supplier_id=supplier.id,
            sku_name="Parle-G 800g",
            category="snacks",
            barcode="8901719101014",
            pack_size=12,
            pack_price=960,
        )
    )
    db.commit()

    body = client_vendor.get("/inventory/by-barcode/8901719101014").json()

    # The product's identity is public; a distributor's pricing is not, and
    # this vendor may have no connection to that distributor at all.
    assert "960" not in str(body)
    assert "pack_price" not in body
