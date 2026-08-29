"""Kirana product knowledge: categories, shelf life, and vernacular aliases.

This is the closest thing the system has to a domain expert. Shelf-life
defaults let a photographed receipt produce an expiry countdown with no extra
input from the vendor (PRD 5.2), and the alias table is what lets a Hindi or
Marathi utterance match an English catalogue row without a translation call.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Category:
    key: str
    label_en: str
    label_hi: str
    label_mr: str

    # Days from intake to spoilage. None means non-perishable.
    shelf_life_days: int | None

    # How sharply demand responds to rain. Umbrellas rise, ice cream falls.
    rain_sensitivity: float

    # How sharply demand responds to a festival window.
    festival_sensitivity: float

    # Fraction of stock held as buffer. Perishables carry less: the cost of a
    # spoiled unit exceeds the cost of a brief stockout.
    service_level: float


CATEGORIES: dict[str, Category] = {
    "dairy": Category("dairy", "Dairy", "डेयरी", "दुग्धजन्य", 3, 0.05, 0.55, 0.90),
    "produce": Category("produce", "Fruits & Vegetables", "फल-सब्ज़ी", "फळे-भाज्या", 4, -0.10, 0.35, 0.88),
    "bakery": Category("bakery", "Bakery", "बेकरी", "बेकरी", 3, 0.00, 0.30, 0.88),
    "staples": Category("staples", "Staples & Grains", "किराना", "किराणा", None, 0.05, 0.45, 0.95),
    "snacks": Category("snacks", "Snacks", "नमकीन", "नमकीन", 120, 0.15, 0.50, 0.93),
    "beverages": Category("beverages", "Beverages", "पेय", "पेये", 180, -0.25, 0.40, 0.93),
    "sweets": Category("sweets", "Sweets", "मिठाई", "मिठाई", 7, 0.00, 0.95, 0.90),
    "personal_care": Category("personal_care", "Personal Care", "व्यक्तिगत देखभाल", "वैयक्तिक काळजी", None, 0.00, 0.15, 0.95),
    "household": Category("household", "Household", "घरेलू", "घरगुती", None, 0.05, 0.20, 0.95),
    "monsoon": Category("monsoon", "Monsoon Goods", "बरसाती सामान", "पावसाळी सामान", None, 0.95, 0.05, 0.92),
}

DEFAULT_CATEGORY = "staples"


def category(key: str) -> Category:
    return CATEGORIES.get(key, CATEGORIES[DEFAULT_CATEGORY])


def shelf_life_for(key: str) -> int | None:
    return category(key).shelf_life_days


# Vernacular aliases, romanised as a vendor would actually say them plus the
# native script Bhashini returns. Matching happens on this table rather than on
# a translation round-trip, which keeps voice entry inside its 10-second budget
# (PRD 2) and working with no connection at all.
ALIASES: dict[str, list[str]] = {
    "Milk": ["doodh", "दूध", "milk", "dudh", "milk packet", "doodh packet"],
    "Curd": ["dahi", "दही", "curd", "yoghurt", "yogurt"],
    "Paneer": ["paneer", "पनीर", "cottage cheese"],
    "Butter": ["makkhan", "मक्खन", "butter", "loni", "लोणी"],
    "Bread": ["bread", "ब्रेड", "pav", "पाव", "double roti"],
    "Eggs": ["anda", "अंडा", "ande", "अंडे", "egg", "eggs"],
    "Rice": ["chawal", "चावल", "rice", "tandul", "तांदूळ"],
    "Wheat Flour": ["atta", "आटा", "wheat flour", "gehun", "गहू", "kanik"],
    "Sugar": ["cheeni", "चीनी", "sugar", "shakkar", "साखर"],
    "Tea": ["chai", "चाय", "chai patti", "tea", "चहा"],
    "Toor Dal": ["toor dal", "तूर दाल", "arhar", "अरहर", "tur dal"],
    "Cooking Oil": ["tel", "तेल", "oil", "cooking oil", "refined"],
    "Salt": ["namak", "नमक", "salt", "meeth", "मीठ"],
    "Onion": ["pyaz", "प्याज", "onion", "kanda", "कांदा"],
    "Potato": ["aloo", "आलू", "potato", "batata", "बटाटा"],
    "Tomato": ["tamatar", "टमाटर", "tomato", "tomato"],
    "Biscuits": ["biscuit", "बिस्किट", "biscuits", "parle"],
    "Namkeen": ["namkeen", "नमकीन", "mixture", "farsan", "फरसाण"],
    "Soft Drink": ["cold drink", "कोल्ड ड्रिंक", "soft drink", "thanda"],
    "Soap": ["sabun", "साबुन", "soap", "साबण"],
    "Detergent": ["surf", "सर्फ", "detergent", "washing powder", "nirma"],
    "Shampoo": ["shampoo", "शैम्पू", "shampu"],
    "Umbrella": ["chhata", "छाता", "umbrella", "chatri", "छत्री"],
    "Raincoat": ["raincoat", "रेनकोट", "barsaati", "बरसाती"],
    "Ladoo": ["ladoo", "लड्डू", "laddu", "modak", "मोदक"],
    "Barfi": ["barfi", "बर्फी", "burfi"],
}


def build_alias_index() -> dict[str, str]:
    """Flatten ALIASES into alias -> canonical name, lowercased.

    Built once and reused; rebuilding per utterance would be wasteful on the
    hot path of every voice entry.
    """
    index: dict[str, str] = {}
    for canonical, aliases in ALIASES.items():
        index[canonical.lower()] = canonical
        for alias in aliases:
            index[alias.lower()] = canonical
    return index


ALIAS_INDEX = build_alias_index()

# Longest-first, so "milk packet" wins over "milk" and the quantity attaches to
# the right noun.
ALIAS_KEYS_BY_LENGTH = sorted(ALIAS_INDEX.keys(), key=len, reverse=True)
