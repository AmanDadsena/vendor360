"""Getting a shop or a wholesaler usable in under two minutes.

Every feature in this product is worthless behind an empty catalogue, and a
kirana store carries two hundred lines. Typing them is not a setup step, it is
a reason to abandon the app on the first evening.

Three routes out of that, in descending order of how much the user has to do:
tap from a master list of what kirana shops actually stock, photograph last
week's bill and let the existing OCR parser read it, or -- for a wholesaler
who already keeps a price list -- paste the spreadsheet.
"""
from __future__ import annotations

import csv
import io
import uuid
from dataclasses import dataclass, field

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import CatalogEntry, InventoryItem, Vendor
from .catalog import CATEGORIES, DEFAULT_CATEGORY, shelf_life_for


@dataclass(frozen=True)
class MasterSku:
    """One line of the starter catalogue.

    `popularity` orders the picker so the twenty things every shop carries are
    the twenty things on screen first. It is a stocking-frequency judgement,
    not sales data -- there is no pilot to learn it from yet, and a stated
    guess that can be corrected beats an implied one that cannot.
    """

    key: str
    name_en: str
    name_hi: str
    name_mr: str
    category: str
    unit: str
    typical_pack: float
    typical_price: float  # per unit, retail
    popularity: int


def _s(
    key, en, hi, mr, category, unit, pack, price, popularity
) -> MasterSku:
    return MasterSku(key, en, hi, mr, category, unit, pack, price, popularity)


# The list a shopkeeper recognises. Names are the ones used over a counter in
# Pune, which is why several are Hindi words written in Latin script -- "atta",
# not "wheat flour".
MASTER_CATALOG: tuple[MasterSku, ...] = (
    # ---------------------------------------------------------- staples
    _s("atta", "Atta (Wheat Flour)", "आटा", "गव्हाचे पीठ", "staples", "kg", 10, 42, 100),
    _s("rice_sona", "Rice (Sona Masoori)", "चावल", "तांदूळ", "staples", "kg", 25, 58, 98),
    _s("rice_basmati", "Basmati Rice", "बासमती चावल", "बासमती तांदूळ", "staples", "kg", 5, 120, 78),
    _s("toor_dal", "Toor Dal", "तूर दाल", "तूर डाळ", "staples", "kg", 5, 165, 95),
    _s("moong_dal", "Moong Dal", "मूंग दाल", "मूग डाळ", "staples", "kg", 5, 130, 82),
    _s("chana_dal", "Chana Dal", "चना दाल", "हरभरा डाळ", "staples", "kg", 5, 95, 80),
    _s("urad_dal", "Urad Dal", "उड़द दाल", "उडीद डाळ", "staples", "kg", 5, 145, 70),
    _s("masoor_dal", "Masoor Dal", "मसूर दाल", "मसूर डाळ", "staples", "kg", 5, 110, 68),
    _s("sugar", "Sugar", "चीनी", "साखर", "staples", "kg", 25, 45, 97),
    _s("salt", "Salt", "नमक", "मीठ", "staples", "kg", 10, 22, 94),
    _s("besan", "Besan", "बेसन", "बेसन", "staples", "kg", 5, 88, 84),
    _s("maida", "Maida", "मैदा", "मैदा", "staples", "kg", 10, 40, 72),
    _s("rava", "Rava / Sooji", "सूजी", "रवा", "staples", "kg", 5, 45, 76),
    _s("poha", "Poha", "पोहा", "पोहे", "staples", "kg", 5, 52, 88),
    _s("sabudana", "Sabudana", "साबूदाना", "साबुदाणा", "staples", "kg", 5, 78, 60),
    _s("oil_sunflower", "Sunflower Oil", "सूरजमुखी तेल", "सूर्यफूल तेल", "staples", "l", 15, 135, 96),
    _s("oil_groundnut", "Groundnut Oil", "मूंगफली तेल", "शेंगदाणा तेल", "staples", "l", 15, 178, 80),
    _s("ghee", "Ghee", "घी", "तूप", "staples", "kg", 1, 620, 74),
    _s("peanuts", "Groundnuts", "मूंगफली", "शेंगदाणे", "staples", "kg", 5, 120, 66),
    _s("jaggery", "Jaggery (Gud)", "गुड़", "गूळ", "staples", "kg", 5, 62, 62),
    # ---------------------------------------------------------- masala
    _s("turmeric", "Turmeric Powder", "हल्दी", "हळद", "staples", "kg", 1, 240, 90),
    _s("chilli_powder", "Red Chilli Powder", "लाल मिर्च", "लाल तिखट", "staples", "kg", 1, 320, 90),
    _s("dhania_powder", "Coriander Powder", "धनिया पाउडर", "धणे पूड", "staples", "kg", 1, 260, 82),
    _s("garam_masala", "Garam Masala", "गरम मसाला", "गरम मसाला", "staples", "kg", 1, 480, 74),
    _s("jeera", "Cumin (Jeera)", "जीरा", "जिरे", "staples", "kg", 1, 420, 80),
    _s("mustard_seed", "Mustard Seeds", "सरसों", "मोहरी", "staples", "kg", 1, 130, 70),
    _s("goda_masala", "Goda Masala", "गोडा मसाला", "गोडा मसाला", "staples", "kg", 1, 420, 58),
    # ---------------------------------------------------------- dairy
    _s("milk", "Milk", "दूध", "दूध", "dairy", "pkt", 12, 28, 100),
    _s("curd", "Curd (Dahi)", "दही", "दही", "dairy", "pkt", 12, 30, 92),
    _s("paneer", "Paneer", "पनीर", "पनीर", "dairy", "pkt", 10, 90, 70),
    _s("butter", "Butter", "मक्खन", "लोणी", "dairy", "pkt", 24, 58, 76),
    _s("cheese", "Cheese Slices", "चीज़", "चीज", "dairy", "pkt", 12, 130, 52),
    _s("buttermilk", "Buttermilk (Chaas)", "छाछ", "ताक", "dairy", "pkt", 24, 15, 68),
    _s("lassi", "Lassi", "लस्सी", "लस्सी", "dairy", "pkt", 24, 25, 60),
    # ---------------------------------------------------------- produce
    _s("onion", "Onion", "प्याज़", "कांदा", "produce", "kg", 20, 32, 99),
    _s("potato", "Potato", "आलू", "बटाटा", "produce", "kg", 20, 28, 99),
    _s("tomato", "Tomato", "टमाटर", "टोमॅटो", "produce", "kg", 10, 40, 97),
    _s("garlic", "Garlic", "लहसुन", "लसूण", "produce", "kg", 5, 160, 86),
    _s("ginger", "Ginger", "अदरक", "आले", "produce", "kg", 5, 120, 84),
    _s("green_chilli", "Green Chilli", "हरी मिर्च", "हिरवी मिरची", "produce", "kg", 2, 80, 88),
    _s("coriander_leaf", "Coriander Leaves", "धनिया", "कोथिंबीर", "produce", "bunch", 20, 15, 85),
    _s("lemon", "Lemon", "नींबू", "लिंबू", "produce", "pc", 50, 5, 80),
    _s("banana", "Banana", "केला", "केळी", "produce", "dozen", 10, 60, 82),
    _s("apple", "Apple", "सेब", "सफरचंद", "produce", "kg", 10, 180, 64),
    # ---------------------------------------------------------- bakery
    _s("bread", "Bread", "ब्रेड", "ब्रेड", "bakery", "pc", 20, 45, 94),
    _s("pav", "Pav", "पाव", "पाव", "bakery", "pkt", 20, 30, 90),
    _s("rusk", "Rusk / Toast", "रस्क", "रस्क", "bakery", "pkt", 24, 40, 74),
    _s("khari", "Khari Biscuit", "खारी", "खारी", "bakery", "pkt", 24, 50, 72),
    # ---------------------------------------------------------- snacks
    _s("parle_g", "Parle-G", "पारले-जी", "पारले-जी", "snacks", "pkt", 48, 10, 100),
    _s("marie", "Marie Biscuit", "मैरी बिस्किट", "मारी बिस्किट", "snacks", "pkt", 24, 30, 84),
    _s("good_day", "Good Day", "गुड डे", "गुड डे", "snacks", "pkt", 24, 30, 82),
    _s("lays", "Potato Chips", "चिप्स", "चिप्स", "snacks", "pkt", 40, 20, 92),
    _s("kurkure", "Kurkure", "कुरकुरे", "कुरकुरे", "snacks", "pkt", 40, 20, 88),
    _s("farsan", "Farsan / Mixture", "फरसाण", "फरसाण", "snacks", "kg", 5, 220, 78),
    _s("chivda", "Chivda", "चिवड़ा", "चिवडा", "snacks", "kg", 5, 200, 76),
    _s("namkeen", "Bhujia Namkeen", "भुजिया", "भुजिया", "snacks", "kg", 5, 240, 74),
    _s("wafers", "Banana Wafers", "केला वेफर", "केळी वेफर", "snacks", "kg", 3, 260, 62),
    # ---------------------------------------------------------- beverages
    _s("tea", "Tea (Chai Patti)", "चाय पत्ती", "चहा पूड", "beverages", "kg", 1, 480, 98),
    _s("coffee", "Instant Coffee", "कॉफ़ी", "कॉफी", "beverages", "pc", 12, 190, 66),
    _s("cola", "Cold Drink", "कोल्ड ड्रिंक", "कोल्ड ड्रिंक", "beverages", "btl", 24, 40, 90),
    _s("water", "Water Bottle", "पानी की बोतल", "पाण्याची बाटली", "beverages", "btl", 24, 20, 92),
    _s("frooti", "Mango Drink", "फ्रूटी", "फ्रुटी", "beverages", "pc", 24, 15, 84),
    _s("energy_drink", "Energy Drink", "एनर्जी ड्रिंक", "एनर्जी ड्रिंक", "beverages", "btl", 24, 50, 48),
    _s("horlicks", "Malt Drink", "हॉर्लिक्स", "हॉर्लिक्स", "beverages", "pc", 12, 260, 56),
    # ---------------------------------------------------------- sweets
    _s("pedha", "Pedha", "पेड़ा", "पेढा", "sweets", "kg", 2, 480, 66),
    _s("laddu", "Besan Laddu", "लड्डू", "लाडू", "sweets", "kg", 2, 420, 68),
    _s("barfi", "Barfi", "बर्फी", "बर्फी", "sweets", "kg", 2, 520, 60),
    _s("gulab_jamun", "Gulab Jamun", "गुलाब जामुन", "गुलाब जामुन", "sweets", "kg", 2, 380, 62),
    _s("soan_papdi", "Soan Papdi", "सोन पापड़ी", "सोन पापडी", "sweets", "pc", 12, 180, 54),
    # ------------------------------------------------------ personal care
    _s("soap_bath", "Bath Soap", "नहाने का साबुन", "आंघोळीचा साबण", "personal_care", "pc", 48, 40, 94),
    _s("shampoo_sachet", "Shampoo Sachet", "शैम्पू", "शाम्पू", "personal_care", "pc", 100, 3, 90),
    _s("toothpaste", "Toothpaste", "टूथपेस्ट", "टूथपेस्ट", "personal_care", "pc", 24, 55, 88),
    _s("toothbrush", "Toothbrush", "टूथब्रश", "टूथब्रश", "personal_care", "pc", 24, 25, 74),
    _s("hair_oil", "Hair Oil", "बाल का तेल", "केसाचे तेल", "personal_care", "btl", 24, 90, 80),
    _s("talc", "Talcum Powder", "पाउडर", "पावडर", "personal_care", "pc", 24, 85, 62),
    _s("sanitary_pad", "Sanitary Pads", "सैनिटरी पैड", "सॅनिटरी पॅड", "personal_care", "pkt", 24, 45, 78),
    _s("razor", "Razor", "रेज़र", "रेझर", "personal_care", "pc", 48, 20, 58),
    _s("face_cream", "Face Cream", "क्रीम", "क्रीम", "personal_care", "pc", 24, 70, 60),
    # ---------------------------------------------------------- household
    _s("detergent_powder", "Detergent Powder", "डिटर्जेंट", "डिटर्जंट", "household", "kg", 10, 75, 95),
    _s("detergent_bar", "Detergent Bar", "कपड़े का साबुन", "कपड्याचा साबण", "household", "pc", 48, 20, 90),
    _s("dishwash_bar", "Dishwash Bar", "बर्तन साबुन", "भांडी साबण", "household", "pc", 48, 20, 88),
    _s("dishwash_liquid", "Dishwash Liquid", "बर्तन लिक्विड", "भांडी लिक्विड", "household", "btl", 12, 110, 70),
    _s("floor_cleaner", "Floor Cleaner", "फ़र्श क्लीनर", "फरशी क्लीनर", "household", "btl", 12, 95, 72),
    _s("phenyl", "Phenyl", "फिनाइल", "फिनेल", "household", "btl", 12, 60, 64),
    _s("agarbatti", "Agarbatti", "अगरबत्ती", "अगरबत्ती", "household", "pkt", 48, 30, 82),
    _s("matchbox", "Matchbox", "माचिस", "काडेपेटी", "household", "pc", 100, 2, 86),
    _s("candle", "Candles", "मोमबत्ती", "मेणबत्ती", "household", "pkt", 48, 25, 60),
    _s("broom", "Broom", "झाड़ू", "झाडू", "household", "pc", 12, 70, 66),
    _s("garbage_bag", "Garbage Bags", "कचरा बैग", "कचरा बॅग", "household", "pkt", 24, 45, 62),
    _s("mosquito_coil", "Mosquito Coil", "मच्छर कॉइल", "डास कॉइल", "household", "pkt", 48, 35, 74),
    _s("battery", "Batteries", "बैटरी", "बॅटरी", "household", "pc", 40, 20, 56),
    # ---------------------------------------------------------- monsoon
    _s("umbrella", "Umbrella", "छाता", "छत्री", "monsoon", "pc", 12, 320, 55),
    _s("raincoat", "Raincoat", "रेनकोट", "रेनकोट", "monsoon", "pc", 10, 450, 48),
    _s("gumboots", "Gumboots", "गमबूट", "गमबूट", "monsoon", "pair", 10, 380, 40),
    _s("plastic_sheet", "Plastic Sheet", "प्लास्टिक शीट", "प्लास्टिक शीट", "monsoon", "pc", 20, 120, 42),
)

MASTER_BY_KEY: dict[str, MasterSku] = {s.key: s for s in MASTER_CATALOG}


def master_catalog(
    *, category: str | None = None, limit: int | None = None
) -> list[MasterSku]:
    """The starter list, most commonly stocked first."""
    rows = [s for s in MASTER_CATALOG if category is None or s.category == category]
    rows.sort(key=lambda s: (-s.popularity, s.name_en))
    return rows[:limit] if limit else rows


def suggested_for_categories(
    categories: list[str], *, per_category: int = 12
) -> list[MasterSku]:
    """The opening screen of the setup flow.

    A shopkeeper picks the two or three things they sell, and gets a short
    list of the obvious lines within them rather than ninety-odd rows to
    scroll. Everything else is still reachable through search.
    """
    picked: list[MasterSku] = []
    for key in categories:
        picked.extend(master_catalog(category=key, limit=per_category))
    return picked


# ------------------------------------------------------------- quick add
@dataclass
class QuickAddResult:
    created: list[InventoryItem] = field(default_factory=list)
    skipped: int = 0


def quick_add(db: Session, vendor: Vendor, keys: list[str]) -> QuickAddResult:
    """Turn a handful of taps into a working inventory.

    Quantities start at zero deliberately. Guessing how much atta a shop has
    would put a wrong number in front of someone on their first screen, and a
    wrong number is harder to trust than an empty one. The first voice entry
    or delivery fills it in.
    """
    result = QuickAddResult()

    existing = {
        name.lower()
        for name in db.scalars(
            select(InventoryItem.sku_name).where(
                InventoryItem.vendor_id == vendor.id
            )
        )
    }

    for key in keys:
        sku = MASTER_BY_KEY.get(key)
        if sku is None or sku.name_en.lower() in existing:
            result.skipped += 1
            continue

        item = InventoryItem(
            vendor_id=vendor.id,
            sku_name=sku.name_en,
            category=sku.category,
            current_qty=0,
            unit=sku.unit,
            # A sane opening margin, editable. Zero would make the first
            # dashboard report every sale as a total loss.
            unit_cost=round(sku.typical_price * 0.85, 2),
            unit_price=sku.typical_price,
            shelf_life_days=shelf_life_for(sku.category),
        )
        db.add(item)
        result.created.append(item)
        existing.add(sku.name_en.lower())

    db.flush()
    return result


# ------------------------------------------------------- price list import
@dataclass
class PriceListRow:
    row: int
    sku_name: str = ""
    category: str = DEFAULT_CATEGORY
    unit: str = "pc"
    pack_size: float = 0.0
    pack_price: float = 0.0
    moq_packs: int = 1
    action: str = "create"  # create | update | skip
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


# Accepted header spellings. Wholesalers export from whatever they use, and
# rejecting a file because it says "rate" instead of "pack_price" would send
# them straight back to the phone.
_ALIASES: dict[str, tuple[str, ...]] = {
    "sku_name": ("sku_name", "sku", "item", "item name", "product", "name", "particulars"),
    "category": ("category", "cat", "type", "group"),
    "unit": ("unit", "uom", "units"),
    "pack_size": ("pack_size", "pack", "pack size", "case size", "qty per pack", "packing"),
    "pack_price": ("pack_price", "price", "rate", "pack price", "case price", "mrp"),
    "moq_packs": ("moq_packs", "moq", "min order", "minimum", "min qty"),
}


def _resolve_headers(fieldnames: list[str] | None) -> dict[str, str]:
    """Map whatever the file calls its columns onto what we need."""
    mapping: dict[str, str] = {}
    for raw in fieldnames or []:
        key = (raw or "").strip().lower()
        for canonical, spellings in _ALIASES.items():
            if key in spellings and canonical not in mapping:
                mapping[canonical] = raw
                break
    return mapping


def parse_price_list(db: Session, supplier_id: uuid.UUID, text: str) -> list[PriceListRow]:
    """Validate a pasted price list without writing anything.

    Preview-then-commit, because a half-applied price list is worse than a
    rejected one: the distributor cannot tell which rows landed, and every
    order priced in between is wrong.
    """
    reader = csv.DictReader(io.StringIO(text.strip()))
    headers = _resolve_headers(reader.fieldnames)

    rows: list[PriceListRow] = []
    missing = [k for k in ("sku_name", "pack_price") if k not in headers]
    if missing:
        return [
            PriceListRow(
                row=0,
                action="skip",
                errors=[
                    "The file needs at least an item name and a price column. "
                    f"Could not find: {', '.join(missing)}."
                ],
            )
        ]

    known = {
        name.lower()
        for name in db.scalars(
            select(CatalogEntry.sku_name).where(
                CatalogEntry.supplier_id == supplier_id
            )
        )
    }
    seen: set[str] = set()

    for index, raw in enumerate(reader, start=1):
        row = _parse_row(index, raw, headers)

        if row.ok:
            lowered = row.sku_name.lower()
            if lowered in seen:
                row.action = "skip"
                row.errors.append("Repeated in this file")
            else:
                seen.add(lowered)
                row.action = "update" if lowered in known else "create"
        else:
            row.action = "skip"

        rows.append(row)

    return rows


def _parse_row(index: int, raw: dict, headers: dict[str, str]) -> PriceListRow:
    row = PriceListRow(row=index)

    def value(key: str) -> str:
        return (raw.get(headers.get(key, ""), "") or "").strip()

    row.sku_name = value("sku_name")
    if not row.sku_name:
        row.errors.append("Missing item name")

    category = value("category").lower()
    row.category = category if category in CATEGORIES else DEFAULT_CATEGORY
    if category and category not in CATEGORIES:
        row.errors.append(f"Unknown category '{category}', filed under staples")

    row.unit = value("unit") or "pc"
    row.pack_size = _number(value("pack_size"), default=1.0)
    row.pack_price = _number(value("pack_price"), default=0.0)
    row.moq_packs = max(1, int(_number(value("moq_packs"), default=1.0)))

    if row.pack_size <= 0:
        row.errors.append("Pack size must be more than zero")
    if row.pack_price <= 0:
        row.errors.append("Price must be more than zero")

    return row


def _number(text: str, *, default: float) -> float:
    """Read a number out of whatever a spreadsheet exported.

    Rupee signs, thousands separators and stray units are all common in a real
    price list and none of them are worth failing a row over.
    """
    if not text:
        return default
    cleaned = "".join(c for c in text if c.isdigit() or c in ".-")
    try:
        return float(cleaned) if cleaned not in ("", "-", ".") else default
    except ValueError:
        return default


def commit_price_list(
    db: Session, supplier_id: uuid.UUID, rows: list[PriceListRow]
) -> tuple[int, int]:
    """Apply the valid rows of a previewed import. Returns (created, updated)."""
    created = updated = 0

    for row in rows:
        if not row.ok or row.action == "skip":
            continue

        entry = db.scalar(
            select(CatalogEntry).where(
                CatalogEntry.supplier_id == supplier_id,
                func.lower(CatalogEntry.sku_name) == row.sku_name.lower(),
            )
        )
        if entry is None:
            db.add(
                CatalogEntry(
                    supplier_id=supplier_id,
                    sku_name=row.sku_name,
                    category=row.category,
                    unit=row.unit,
                    pack_size=row.pack_size,
                    pack_price=row.pack_price,
                    moq_packs=row.moq_packs,
                )
            )
            created += 1
        else:
            entry.category = row.category
            entry.unit = row.unit
            entry.pack_size = row.pack_size
            entry.pack_price = row.pack_price
            entry.moq_packs = row.moq_packs
            # Re-listing something withdrawn is the obvious intent of including
            # it in a fresh price list.
            entry.active = True
            updated += 1

    db.flush()
    return created, updated
