"""Getting set up without typing two hundred lines (TC-N**)."""
from __future__ import annotations

import pytest
from sqlalchemy import select

from app.models import CatalogEntry, InventoryItem
from app.services.catalog import CATEGORIES
from app.services.onboarding import (
    MASTER_BY_KEY,
    MASTER_CATALOG,
    commit_price_list,
    master_catalog,
    parse_price_list,
    quick_add,
    suggested_for_categories,
)


# --------------------------------------------------- TC-N01 master catalogue
def test_tc_n01_every_master_sku_uses_a_known_category():
    """A typo here would silently give an item the wrong shelf life."""
    for sku in MASTER_CATALOG:
        assert sku.category in CATEGORIES, f"{sku.key} has category {sku.category}"


def test_tc_n01_master_keys_are_unique():
    keys = [s.key for s in MASTER_CATALOG]
    assert len(keys) == len(set(keys))


def test_tc_n01_the_catalogue_is_big_enough_to_be_useful():
    """A starter list that misses half a shop's lines is not a shortcut."""
    assert len(MASTER_CATALOG) >= 90
    # And it spans the taxonomy rather than clustering in one aisle.
    covered = {s.category for s in MASTER_CATALOG}
    assert covered == set(CATEGORIES)


def test_tc_n01_most_stocked_items_come_first(db):
    rows = master_catalog(limit=10)
    names = [r.name_en for r in rows]

    assert "Parle-G" in names or "Milk" in names
    populations = [r.popularity for r in rows]
    assert populations == sorted(populations, reverse=True)


def test_tc_n01_suggestions_follow_the_chosen_aisles():
    picked = suggested_for_categories(["dairy", "produce"], per_category=5)

    assert len(picked) == 10
    assert {s.category for s in picked} == {"dairy", "produce"}


# ---------------------------------------------------------- TC-N02 quick add
def test_tc_n02_tapping_a_few_skus_creates_a_working_inventory(db, vendor):
    result = quick_add(db, vendor, ["atta", "milk", "parle_g"])
    db.commit()

    assert len(result.created) == 3
    assert result.skipped == 0

    items = db.scalars(
        select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
    ).all()
    assert {i.sku_name for i in items} == {"Atta (Wheat Flour)", "Milk", "Parle-G"}


def test_tc_n02_perishables_arrive_with_their_shelf_life_set(db, vendor):
    """The expiry board must work from the first day, with no extra input."""
    quick_add(db, vendor, ["milk", "atta"])
    db.commit()

    items = {
        i.sku_name: i
        for i in db.scalars(
            select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
        )
    }

    assert items["Milk"].shelf_life_days == 3
    # Atta is a staple: non-perishable, so no countdown at all.
    assert items["Atta (Wheat Flour)"].shelf_life_days is None


def test_tc_n02_quantities_start_at_zero_rather_than_guessed(db, vendor):
    """A wrong opening number is harder to trust than an empty one."""
    quick_add(db, vendor, ["milk"])
    db.commit()

    item = db.scalar(
        select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
    )
    assert item.current_qty == 0
    # But priced, so the first sale is not reported as a total loss.
    assert item.unit_price > 0
    assert item.unit_cost < item.unit_price


def test_tc_n02_adding_the_same_sku_twice_is_a_no_op(db, vendor):
    quick_add(db, vendor, ["milk"])
    db.commit()

    result = quick_add(db, vendor, ["milk", "atta"])
    db.commit()

    assert len(result.created) == 1
    assert result.skipped == 1


def test_tc_n02_an_unknown_key_is_skipped_not_fatal(db, vendor):
    result = quick_add(db, vendor, ["milk", "not_a_real_sku"])
    db.commit()

    assert len(result.created) == 1
    assert result.skipped == 1


def test_tc_n02_quick_add_respects_an_existing_hand_typed_item(db, vendor, milk):
    """`milk` the fixture is already called "Milk"; do not duplicate the shelf."""
    result = quick_add(db, vendor, ["milk"])
    db.commit()

    assert result.created == []
    assert result.skipped == 1


# ------------------------------------------------------- TC-N03 price lists
GOOD_CSV = """sku_name,category,unit,pack_size,pack_price,moq_packs
Milk,dairy,pkt,12,276,1
Atta,staples,kg,10,420,2
Parle-G,snacks,pkt,48,432,1
"""


def test_tc_n03_a_clean_price_list_previews_as_all_creates(db, supplier):
    rows = parse_price_list(db, supplier.id, GOOD_CSV)

    assert len(rows) == 3
    assert all(r.ok for r in rows)
    assert {r.action for r in rows} == {"create"}
    assert rows[0].pack_price == 276
    assert rows[1].moq_packs == 2


def test_tc_n03_preview_writes_nothing(db, supplier):
    parse_price_list(db, supplier.id, GOOD_CSV)

    assert db.scalars(select(CatalogEntry)).all() == []


def test_tc_n03_committing_creates_then_updates(db, supplier):
    rows = parse_price_list(db, supplier.id, GOOD_CSV)
    created, updated = commit_price_list(db, supplier.id, rows)
    db.commit()

    assert (created, updated) == (3, 0)

    # The same file again is three updates, not three duplicates.
    rows = parse_price_list(db, supplier.id, GOOD_CSV)
    assert {r.action for r in rows} == {"update"}

    created, updated = commit_price_list(db, supplier.id, rows)
    db.commit()

    assert (created, updated) == (0, 3)
    assert len(db.scalars(select(CatalogEntry)).all()) == 3


def test_tc_n03_headers_are_matched_loosely(db, supplier):
    """Wholesalers export from whatever they use; "rate" is still a price."""
    messy = """Item,Packing,Rate,MOQ
Milk,12,276,1
Atta,10,420,2
"""
    rows = parse_price_list(db, supplier.id, messy)

    assert all(r.ok for r in rows)
    assert rows[0].sku_name == "Milk"
    assert rows[0].pack_size == 12
    assert rows[0].pack_price == 276


def test_tc_n03_rupee_signs_and_commas_do_not_fail_a_row(db, supplier):
    dirty = """sku_name,pack_size,pack_price
Basmati Rice,25,"₹3,250"
Ghee,15,"₹9,300.50"
"""
    rows = parse_price_list(db, supplier.id, dirty)

    assert all(r.ok for r in rows)
    assert rows[0].pack_price == 3250
    assert rows[1].pack_price == pytest.approx(9300.50)


def test_tc_n03_bad_rows_are_flagged_and_the_rest_still_import(db, supplier):
    mixed = """sku_name,category,unit,pack_size,pack_price
Milk,dairy,pkt,12,276
,dairy,pkt,12,300
Ghee,dairy,kg,0,620
Sugar,dairy,kg,10,0
"""
    rows = parse_price_list(db, supplier.id, mixed)

    assert rows[0].ok
    assert "Missing item name" in rows[1].errors
    assert any("Pack size" in e for e in rows[2].errors)
    assert any("Price" in e for e in rows[3].errors)

    created, updated = commit_price_list(db, supplier.id, rows)
    db.commit()

    assert (created, updated) == (1, 0)


def test_tc_n03_an_unknown_category_is_filed_not_rejected(db, supplier):
    odd = """sku_name,category,unit,pack_size,pack_price
Widget,gadgets,pc,1,50
"""
    rows = parse_price_list(db, supplier.id, odd)

    assert rows[0].category == "staples"
    assert any("Unknown category" in e for e in rows[0].errors)
    # Flagged, but not fatal — the distributor can fix the aisle afterwards.
    assert rows[0].action == "skip"


def test_tc_n03_a_repeated_row_is_only_applied_once(db, supplier):
    dupes = """sku_name,pack_size,pack_price
Milk,12,276
Milk,12,300
"""
    rows = parse_price_list(db, supplier.id, dupes)

    assert rows[0].action == "create"
    assert rows[1].action == "skip"
    assert "Repeated in this file" in rows[1].errors


def test_tc_n03_a_file_with_no_usable_columns_says_so(db, supplier):
    rows = parse_price_list(db, supplier.id, "foo,bar\n1,2\n")

    assert len(rows) == 1
    assert rows[0].action == "skip"
    assert "item name" in rows[0].errors[0]


def test_tc_n03_re_listing_reactivates_a_withdrawn_line(db, supplier, milk_listing):
    milk_listing.active = False
    db.commit()

    rows = parse_price_list(db, supplier.id, "sku_name,pack_size,pack_price\nMilk,12,300\n")
    commit_price_list(db, supplier.id, rows)
    db.commit()
    db.refresh(milk_listing)

    assert milk_listing.active is True
    assert milk_listing.pack_price == 300


def test_master_lookup_is_indexed_by_key():
    assert MASTER_BY_KEY["milk"].name_en == "Milk"
    assert MASTER_BY_KEY["parle_g"].category == "snacks"
