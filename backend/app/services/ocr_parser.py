"""Wholesale receipt parsing (PRD 5.2, TC-O01..O04).

Takes the raw text an OCR engine returns from a photographed supplier receipt
and turns it into stock intake with expiry dates already computed.

The design guide is explicit that a blurry receipt must not block the whole
capture: low-confidence rows are highlighted for a quick check while the rest
proceed (TC-O02). So every line carries its own confidence, and the caller
decides per row rather than per receipt.

Expiry is derived from the category shelf life and the capture date, which is
what makes the countdown automatic from a single photograph (TC-O04).
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from datetime import date, timedelta

from .catalog import ALIAS_INDEX, ALIAS_KEYS_BY_LENGTH, shelf_life_for
from .nlp_parser import _category_for

# Below this a row is highlighted for manual confirmation.
REVIEW_THRESHOLD = 0.70

# Lines that are receipt furniture rather than stock.
_NOISE_PATTERNS = [
    r"^\s*$",
    r"gst\s*(no|in|:)",
    r"^\s*(sub\s*)?total",
    r"invoice|bill\s*no|receipt|challan",
    r"^\s*(date|dt)\b",
    r"phone|mobile|contact|address",
    r"thank\s*you|visit\s*again",
    r"^\s*[-=*_]{3,}\s*$",
    r"^\s*(item|particulars|description)\s",
    r"cgst|sgst|igst|tax|discount|round\s*off",
    r"amount\s*in\s*words",
]
_NOISE = re.compile("|".join(_NOISE_PATTERNS), re.IGNORECASE)

# Unit tokens as they appear in pack descriptions: "500ml", "1kg", "250 gm".
_PACK = re.compile(
    r"(\d+(?:\.\d+)?)\s*(kg|kgs|g|gm|gms|gram|ml|l|ltr|litre|liter|pc|pcs|pkt|packet)\b",
    re.IGNORECASE,
)

_UNIT_CANON = {
    "kg": "kg", "kgs": "kg", "g": "g", "gm": "g", "gms": "g", "gram": "g",
    "ml": "ml", "l": "l", "ltr": "l", "litre": "l", "liter": "l",
    "pc": "pc", "pcs": "pc", "pkt": "pkt", "packet": "pkt",
}


@dataclass
class ReceiptLine:
    raw: str
    sku_name: str | None
    matched_alias: str | None
    qty: float | None
    unit: str | None
    rate: float | None
    amount: float | None
    category: str | None
    shelf_life_days: int | None
    expires_on: date | None
    confidence: float
    needs_review: bool
    issues: list[str] = field(default_factory=list)


@dataclass
class ReceiptResult:
    supplier: str | None
    captured_on: date
    lines: list[ReceiptLine]
    stated_total: float | None
    computed_total: float
    total_matches: bool
    overall_confidence: float

    @property
    def review_count(self) -> int:
        return sum(1 for line in self.lines if line.needs_review)

    @property
    def needs_review(self) -> bool:
        return self.review_count > 0 or not self.total_matches


def _normalise(text: str) -> str:
    text = unicodedata.normalize("NFKC", text)
    # OCR routinely reads O for 0 and l/I for 1 inside numbers. Fixing them
    # only when surrounded by digits avoids mangling product names.
    text = re.sub(r"(?<=\d)[Oo](?=\d)", "0", text)
    text = re.sub(r"(?<=\d)[lI](?=\d)", "1", text)
    return text


def _numbers_in(line: str) -> list[float]:
    """Trailing numeric columns: quantity, rate, amount.

    Numbers embedded in a pack size ("500ml") are excluded first, otherwise a
    500ml pack is read as a quantity of 500.
    """
    stripped = _PACK.sub(" ", line)
    return [
        float(n.replace(",", ""))
        for n in re.findall(r"\d[\d,]*\.?\d*", stripped)
    ]


def _match_product(line: str) -> tuple[str | None, str | None]:
    lowered = line.lower()
    for alias in ALIAS_KEYS_BY_LENGTH:
        if re.search(rf"(?<![\wऀ-ॿ]){re.escape(alias)}(?![\wऀ-ॿ])", lowered):
            return ALIAS_INDEX[alias], alias
    return None, None


def parse_receipt(
    raw_text: str,
    *,
    captured_on: date | None = None,
    ocr_confidence: float = 1.0,
    supplier_hint: str | None = None,
) -> ReceiptResult:
    """Parse OCR text into stock lines with expiry already computed.

    `ocr_confidence` is the engine's own score for the image. It multiplies
    through every row, so a photograph taken in poor light cannot produce
    confidently-wrong intake -- which is exactly the TC-O02 requirement.
    """
    captured_on = captured_on or date.today()
    text = _normalise(raw_text)
    raw_lines = [ln.strip() for ln in text.splitlines()]

    supplier = supplier_hint
    if supplier is None:
        for ln in raw_lines[:3]:
            if ln and not _NOISE.search(ln) and not re.search(r"\d{3,}", ln):
                supplier = ln.strip()
                break

    stated_total: float | None = None
    lines: list[ReceiptLine] = []

    for ln in raw_lines:
        if not ln:
            continue

        if re.search(r"^\s*(grand\s*)?total", ln, re.IGNORECASE):
            nums = _numbers_in(ln)
            if nums:
                stated_total = nums[-1]
            continue

        if _NOISE.search(ln):
            continue

        sku, alias = _match_product(ln)
        nums = _numbers_in(ln)

        # A line with neither a known product nor any numbers is not stock.
        if sku is None and not nums:
            continue

        issues: list[str] = []
        confidence = ocr_confidence

        if sku is None:
            issues.append("product not recognised")
            confidence *= 0.45

        # Pack size, e.g. "Amul Milk 500ml".
        unit = None
        pack = _PACK.search(ln)
        if pack:
            unit = _UNIT_CANON.get(pack.group(2).lower())

        qty = rate = amount = None
        if len(nums) >= 3:
            # The common layout: qty, rate, amount.
            qty, rate, amount = nums[-3], nums[-2], nums[-1]
            # Arithmetic is the strongest signal a row was read correctly.
            if rate and abs((qty * rate) - amount) > max(1.0, amount * 0.02):
                issues.append("qty x rate does not match amount")
                confidence *= 0.55
            else:
                confidence *= 1.0
        elif len(nums) == 2:
            qty, amount = nums
            rate = round(amount / qty, 2) if qty else None
            issues.append("rate inferred from amount")
            confidence *= 0.8
        elif len(nums) == 1:
            qty = nums[0]
            issues.append("no price column found")
            confidence *= 0.6
        else:
            issues.append("no quantity found")
            confidence *= 0.4

        if qty is not None and qty <= 0:
            issues.append("non-positive quantity")
            confidence *= 0.4

        category = _category_for(sku) if sku else None
        shelf_days = shelf_life_for(category) if category else None
        expires = captured_on + timedelta(days=shelf_days) if shelf_days else None

        confidence = round(min(1.0, confidence), 3)
        lines.append(
            ReceiptLine(
                raw=ln,
                sku_name=sku,
                matched_alias=alias,
                qty=qty,
                unit=unit,
                rate=rate,
                amount=amount,
                category=category,
                shelf_life_days=shelf_days,
                expires_on=expires,
                confidence=confidence,
                needs_review=confidence < REVIEW_THRESHOLD,
                issues=issues,
            )
        )

    computed = round(sum(l.amount for l in lines if l.amount), 2)

    # A stated total that disagrees with the sum means a row was missed or
    # misread. Cheap to check, and it catches the failure OCR is worst at:
    # dropping a line entirely, which no per-row confidence can detect.
    total_matches = (
        stated_total is None
        or abs(stated_total - computed) <= max(1.0, stated_total * 0.02)
    )

    overall = (
        round(sum(l.confidence for l in lines) / len(lines), 3) if lines else 0.0
    )

    return ReceiptResult(
        supplier=supplier,
        captured_on=captured_on,
        lines=lines,
        stated_total=stated_total,
        computed_total=computed,
        total_matches=total_matches,
        overall_confidence=overall,
    )
