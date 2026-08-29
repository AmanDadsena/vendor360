"""Vernacular utterance parsing (PRD 5.2, TC-V01..V05).

Turns what Bhashini transcribed -- "20 doodh packet aur 5 kilo chawal beche" --
into structured inventory movements. Runs on rules rather than a language
model, for three reasons: the vocabulary of a stock update is small and closed,
it must work with no connectivity, and every extraction has to carry an
honest confidence the UI can act on.

Confidence is the point. ASR mishears, and the design guide is explicit that
nothing commits without a confirm step; a parser that always claimed certainty
would make that step meaningless. Anything below `REVIEW_THRESHOLD` is returned
flagged so the vendor is shown exactly which token to check (TC-V02).
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

from .catalog import ALIAS_INDEX, ALIAS_KEYS_BY_LENGTH, CATEGORIES

# Below this, the row is surfaced for confirmation rather than applied.
REVIEW_THRESHOLD = 0.72


# Intent verbs. A stock update is almost always one of three movements, and
# vendors say them in a predictable handful of ways across the three languages.
_SALE_WORDS = {
    "beche", "becha", "bechi", "bech", "बेचे", "बेचा", "बेची",
    "sold", "sale", "sell", "gaya", "gaye", "गया", "गये", "गए",
    "vikle", "विकले", "विकला", "khatam", "ख़तम", "खत्म",
}
_RESTOCK_WORDS = {
    "aaya", "aaye", "aayi", "आया", "आये", "आई",
    "liya", "liye", "लिया", "लिये", "kharida", "ख़रीदा", "खरीदा",
    "bought", "restock", "stock", "added", "add", "purchase",
    "ghetla", "घेतला", "आणला", "aanla", "naya", "नया",
}
_WASTE_WORDS = {
    "kharab", "ख़राब", "खराब", "waste", "wasted", "spoiled", "spoilt",
    "expired", "phenka", "फेंका", "फेका", "sadla", "सडला", "bekar", "बेकार",
    "damaged", "toota", "टूटा",
}

# Romanised and Devanagari number words. Vendors mix scripts freely, so both
# forms map to the same value.
_NUM_WORDS: dict[str, float] = {
    "ek": 1, "एक": 1, "do": 2, "दो": 2, "दोन": 2,
    "teen": 3, "तीन": 3, "char": 4, "चार": 4,
    "panch": 5, "पांच": 5, "पाच": 5, "paanch": 5,
    "chhe": 6, "छह": 6, "सहा": 6, "che": 6,
    "saat": 7, "सात": 7, "aath": 8, "आठ": 8,
    "nau": 9, "नौ": 9, "नऊ": 9,
    "das": 10, "दस": 10, "दहा": 10,
    "gyarah": 11, "ग्यारह": 11, "barah": 12, "बारह": 12,
    "pandrah": 15, "पंद्रह": 15, "पंधरा": 15,
    "bees": 20, "बीस": 20, "वीस": 20,
    "pachees": 25, "पच्चीस": 25,
    "tees": 30, "तीस": 30, "chalees": 40, "चालीस": 40,
    "pachas": 50, "पचास": 50, "पन्नास": 50,
    "sau": 100, "सौ": 100, "शंभर": 100,
    "adha": 0.5, "आधा": 0.5, "अर्धा": 0.5, "half": 0.5,
    "dedh": 1.5, "डेढ़": 1.5, "देड": 1.5,
    "paav": 0.25, "पाव": 0.25, "quarter": 0.25,
}

_UNIT_WORDS: dict[str, str] = {
    "kilo": "kg", "kg": "kg", "kilos": "kg", "किलो": "kg", "kilogram": "kg",
    "gram": "g", "grams": "g", "ग्राम": "g", "gm": "g",
    "litre": "l", "liter": "l", "litres": "l", "ltr": "l", "लीटर": "l",
    "ml": "ml", "एमएल": "ml",
    "packet": "pkt", "packets": "pkt", "पैकेट": "pkt", "pouch": "pkt",
    "piece": "pc", "pieces": "pc", "pcs": "pc", "nag": "pc", "नग": "pc",
    "dozen": "dz", "दर्जन": "dz",
    "box": "box", "बॉक्स": "box", "peti": "box", "पेटी": "box",
    "bottle": "btl", "बोतल": "btl",
    "bag": "bag", "बोरी": "bag", "bori": "bag",
}

# Devanagari digits share Unicode's decimal property, so normalisation handles
# them without a per-character table.
_DEVANAGARI_DIGITS = "०१२३४५६७८९"


@dataclass
class ParsedLine:
    sku_name: str
    qty: float
    unit: str | None
    movement: str          # sale | restock | wastage
    confidence: float
    matched_text: str
    needs_review: bool
    category: str | None = None


@dataclass
class ParseResult:
    transcript: str
    language: str
    movement: str
    lines: list[ParsedLine] = field(default_factory=list)
    unmatched_tokens: list[str] = field(default_factory=list)
    overall_confidence: float = 0.0

    @property
    def needs_review(self) -> bool:
        return any(line.needs_review for line in self.lines) or not self.lines


def normalise(text: str) -> str:
    """Lowercase, convert Devanagari digits, and collapse whitespace.

    NFKC first so composed and decomposed Devanagari forms compare equal --
    ASR output and the alias table are not guaranteed to agree on composition,
    and a mismatch there silently fails every lookup.
    """
    text = unicodedata.normalize("NFKC", text)
    out = []
    for ch in text:
        if ch in _DEVANAGARI_DIGITS:
            out.append(str(_DEVANAGARI_DIGITS.index(ch)))
        else:
            out.append(ch)
    text = "".join(out).lower()
    return re.sub(r"\s+", " ", text).strip()


def detect_movement(text: str) -> tuple[str, float]:
    """Classify the utterance as a sale, restock, or wastage.

    Wastage is checked first: "kharab ho gaya" contains a sale verb, and
    reading it as a sale would both overstate revenue and hide the spoilage the
    Health Score depends on seeing.
    """
    tokens = set(re.findall(r"[\wऀ-ॿ]+", text))

    if tokens & _WASTE_WORDS:
        return "wastage", 0.95
    if tokens & _RESTOCK_WORDS:
        return "restock", 0.92
    if tokens & _SALE_WORDS:
        return "sale", 0.95

    # Vendors often omit the verb entirely -- "bees doodh packet" while serving
    # a customer. Sale is overwhelmingly the most frequent action, so it is the
    # right default, but the lowered confidence sends it to the confirm step.
    return "sale", 0.62


def _parse_quantity(token: str) -> float | None:
    if token in _NUM_WORDS:
        return _NUM_WORDS[token]
    if re.fullmatch(r"\d+(\.\d+)?", token):
        return float(token)
    # "2kg" with no space, which ASR produces regularly.
    m = re.fullmatch(r"(\d+(?:\.\d+)?)([a-zऀ-ॿ]+)", token)
    if m and m.group(2) in _UNIT_WORDS:
        return float(m.group(1))
    return None


def _find_units(text: str) -> list[tuple[int, int, str]]:
    """Every unit mention in the text, as (start, end, canonical_unit)."""
    found: list[tuple[int, int, str]] = []
    for word, canonical in _UNIT_WORDS.items():
        for m in re.finditer(rf"(?<![\wऀ-ॿ]){re.escape(word)}(?![\wऀ-ॿ])", text):
            found.append((m.start(), m.end(), canonical))
    return found


# Beyond this many characters a unit is too far from the product to plausibly
# belong to it, and no unit is better than the wrong one.
_UNIT_MAX_DISTANCE = 18


def _nearest_unit(
    text: str, start: int, end: int, all_spans: list[tuple[int, int]]
) -> str | None:
    """The unit belonging to the product mention at [start, end).

    Ownership is decided by proximity, and a unit closer to a *different*
    product is not stolen. In "20 doodh packet aur 5 kilo chawal", both units
    sit inside any generous window around either product, so a window-and-first-
    match approach hands milk the rice's kilos -- and does it non-
    deterministically, since the winner depends on dictionary order.
    """
    best: tuple[int, str] | None = None

    for u_start, u_end, canonical in _find_units(text):
        distance = u_start - end if u_start >= end else start - u_end
        if distance > _UNIT_MAX_DISTANCE:
            continue

        # Skip units that sit closer to some other product mention.
        stolen = False
        for o_start, o_end in all_spans:
            if (o_start, o_end) == (start, end):
                continue
            other = u_start - o_end if u_start >= o_end else o_start - u_end
            if other < distance:
                stolen = True
                break
        if stolen:
            continue

        if best is None or distance < best[0]:
            best = (distance, canonical)

    return best[1] if best else None


def parse_utterance(
    transcript: str,
    *,
    language: str = "hi",
    known_skus: list[str] | None = None,
    asr_confidence: float = 1.0,
) -> ParseResult:
    """Extract inventory movements from a transcribed utterance.

    `known_skus` scopes matching to the vendor's own catalogue, so a store that
    does not sell umbrellas cannot have one conjured by a misheard word.
    `asr_confidence` from Bhashini multiplies through: a shaky transcription
    cannot yield a confident extraction no matter how cleanly it parses.
    """
    text = normalise(transcript)
    movement, move_conf = detect_movement(text)

    known = {s.lower() for s in known_skus} if known_skus else None

    # Locate every product mention first, longest alias first so "milk packet"
    # is not shadowed by "milk".
    spans: list[tuple[int, int, str]] = []
    claimed: list[tuple[int, int]] = []

    for alias in ALIAS_KEYS_BY_LENGTH:
        for m in re.finditer(rf"(?<![\wऀ-ॿ]){re.escape(alias)}(?![\wऀ-ॿ])", text):
            if any(m.start() < e and m.end() > s for s, e in claimed):
                continue
            canonical = ALIAS_INDEX[alias]
            if known is not None and canonical.lower() not in known:
                continue
            claimed.append((m.start(), m.end()))
            spans.append((m.start(), m.end(), canonical))

    spans.sort()
    tokens = list(re.finditer(r"[\wऀ-ॿ.]+", text))
    lines: list[ParsedLine] = []

    for start, end, canonical in spans:
        # The quantity is the nearest number before the product name, which is
        # how these sentences are constructed in all three languages. A number
        # after the name is accepted as a weaker fallback.
        qty, unit, qty_conf = None, None, 0.0

        before = [t for t in tokens if t.end() <= start]
        for tok in reversed(before[-4:]):
            value = _parse_quantity(tok.group())
            if value is not None:
                qty, qty_conf = value, 0.95
                break

        if qty is None:
            after = [t for t in tokens if t.start() >= end]
            for tok in after[:3]:
                value = _parse_quantity(tok.group())
                if value is not None:
                    qty, qty_conf = value, 0.70
                    break

        if qty is None:
            # No number at all. Assuming 1 is a guess, not a reading, so it is
            # flagged low enough to guarantee the confirm step.
            qty, qty_conf = 1.0, 0.40

        unit = _nearest_unit(text, start, end, [(s, e) for s, e, _ in spans])

        confidence = round(move_conf * qty_conf * asr_confidence, 3)
        category_key = _category_for(canonical)

        lines.append(
            ParsedLine(
                sku_name=canonical,
                qty=qty,
                unit=unit,
                movement=movement,
                confidence=confidence,
                matched_text=text[start:end],
                needs_review=confidence < REVIEW_THRESHOLD,
                category=category_key,
            )
        )

    matched_spans = [(s, e) for s, e, _ in spans]
    unmatched = [
        t.group()
        for t in tokens
        if not any(t.start() < e and t.end() > s for s, e in matched_spans)
        and t.group() not in _NUM_WORDS
        and t.group() not in _UNIT_WORDS
        and not re.fullmatch(r"\d+(\.\d+)?", t.group())
        and t.group() not in (_SALE_WORDS | _RESTOCK_WORDS | _WASTE_WORDS)
        and t.group() not in {"aur", "और", "and", "ani", "आणि", "ka", "ki", "ke", "का", "की", "के"}
    ]

    overall = round(sum(l.confidence for l in lines) / len(lines), 3) if lines else 0.0

    return ParseResult(
        transcript=transcript,
        language=language,
        movement=movement,
        lines=lines,
        unmatched_tokens=unmatched,
        overall_confidence=overall,
    )


_CATEGORY_BY_SKU: dict[str, str] = {
    "Milk": "dairy", "Curd": "dairy", "Paneer": "dairy", "Butter": "dairy",
    "Eggs": "dairy", "Bread": "bakery",
    "Rice": "staples", "Wheat Flour": "staples", "Sugar": "staples",
    "Tea": "staples", "Toor Dal": "staples", "Cooking Oil": "staples",
    "Salt": "staples",
    "Onion": "produce", "Potato": "produce", "Tomato": "produce",
    "Biscuits": "snacks", "Namkeen": "snacks",
    "Soft Drink": "beverages",
    "Soap": "personal_care", "Shampoo": "personal_care",
    "Detergent": "household",
    "Umbrella": "monsoon", "Raincoat": "monsoon",
    "Ladoo": "sweets", "Barfi": "sweets",
}


def _category_for(sku: str) -> str:
    return _CATEGORY_BY_SKU.get(sku, "staples")
