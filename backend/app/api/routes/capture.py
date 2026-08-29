"""Voice and OCR capture endpoints (TRD 4).

Both default to `commit=False`, returning a parse for confirmation without
touching inventory. The design guide requires a confirm step on every voice and
OCR entry because ASR and OCR are imperfect and trust has to be earned; making
preview the default means a client cannot skip that step by omission.
"""
from __future__ import annotations

import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...core.db import get_db, utcnow
from ...core.security import current_vendor
from ...models import InventoryItem, Transaction, Vendor
from ...schemas import (
    OcrEntryIn,
    OcrEntryOut,
    ParsedLineOut,
    ReceiptLineOut,
    VoiceEntryIn,
    VoiceEntryOut,
)
from ...services.catalog import shelf_life_for
from ...services.nlp_parser import parse_utterance
from ...services.ocr_parser import parse_receipt
from ...services.sync import MOVEMENT_SIGN
from .inventory import refresh_reorder_point

router = APIRouter(tags=["capture"])


def _vendor_items(db: Session, vendor_id: uuid.UUID) -> dict[str, InventoryItem]:
    rows = db.scalars(
        select(InventoryItem).where(InventoryItem.vendor_id == vendor_id)
    ).all()
    return {item.sku_name.lower(): item for item in rows}


@router.post("/inventory/voice-entry", response_model=VoiceEntryOut)
def voice_entry(
    body: VoiceEntryIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Parse a transcribed utterance into inventory movements."""
    catalogue = _vendor_items(db, vendor.id)

    parsed = parse_utterance(
        body.transcript,
        language=body.language,
        asr_confidence=body.asr_confidence,
    )

    lines: list[ParsedLineOut] = []
    for line in parsed.lines:
        existing = catalogue.get(line.sku_name.lower())
        lines.append(
            ParsedLineOut(
                sku_name=line.sku_name,
                qty=line.qty,
                unit=line.unit,
                movement=line.movement,
                confidence=line.confidence,
                needs_review=line.needs_review,
                matched_text=line.matched_text,
                category=line.category,
                item_id=existing.id if existing else None,
                known_item=existing is not None,
            )
        )

    committed = False
    # Committing requires an explicit request AND a clean parse. A client that
    # sets commit=True on a low-confidence transcript still gets the confirm
    # step, because the rule belongs on the server, not in the UI.
    if body.commit and lines and not parsed.needs_review:
        _commit_lines(db, vendor, lines)
        committed = True

    return VoiceEntryOut(
        transcript=parsed.transcript,
        language=parsed.language,
        movement=parsed.movement,
        overall_confidence=parsed.overall_confidence,
        needs_review=parsed.needs_review,
        lines=lines,
        unmatched_tokens=parsed.unmatched_tokens,
        committed=committed,
    )


@router.post("/inventory/voice-entry/confirm", response_model=VoiceEntryOut)
def voice_confirm(
    body: VoiceEntryIn,
    lines: list[ParsedLineOut],
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Apply lines the vendor reviewed and corrected on screen."""
    _commit_lines(db, vendor, lines)
    return VoiceEntryOut(
        transcript=body.transcript,
        language=body.language,
        movement=lines[0].movement if lines else "sale",
        overall_confidence=1.0,
        needs_review=False,
        lines=lines,
        unmatched_tokens=[],
        committed=True,
    )


def _commit_lines(db: Session, vendor: Vendor, lines: list[ParsedLineOut]) -> None:
    """Apply confirmed voice lines, creating unknown SKUs as they appear.

    A vendor saying a product name the catalogue has never seen is adding it to
    their catalogue, not making a mistake. Refusing would force them to a
    keyboard, which is the barrier this feature exists to remove.
    """
    for line in lines:
        item = None
        if line.item_id:
            item = db.scalar(
                select(InventoryItem).where(
                    InventoryItem.id == line.item_id,
                    InventoryItem.vendor_id == vendor.id,
                )
            )
        if item is None:
            item = db.scalar(
                select(InventoryItem).where(
                    InventoryItem.vendor_id == vendor.id,
                    InventoryItem.sku_name == line.sku_name,
                )
            )
        if item is None:
            item = InventoryItem(
                vendor_id=vendor.id,
                sku_name=line.sku_name,
                category=line.category or "staples",
                unit=line.unit or "pc",
                current_qty=0,
                shelf_life_days=shelf_life_for(line.category or "staples"),
            )
            db.add(item)
            db.flush()

        sign = MOVEMENT_SIGN.get(line.movement, -1.0)
        item.current_qty = max(0.0, item.current_qty + sign * line.qty)
        item.last_updated = utcnow()

        db.add(
            Transaction(
                vendor_id=vendor.id,
                item_id=item.id,
                type=line.movement,
                qty=line.qty,
                unit_value=item.unit_price if line.movement == "sale" else item.unit_cost,
                source="voice",
                confidence=line.confidence,
                raw_text=line.matched_text,
                occurred_at=utcnow(),
            )
        )

    db.commit()

    for line in lines:
        item = db.scalar(
            select(InventoryItem).where(
                InventoryItem.vendor_id == vendor.id,
                InventoryItem.sku_name == line.sku_name,
            )
        )
        if item:
            refresh_reorder_point(db, item, vendor)


@router.post("/inventory/ocr-entry", response_model=OcrEntryOut)
def ocr_entry(
    body: OcrEntryIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Parse a photographed wholesale receipt into stock intake."""
    result = parse_receipt(
        body.raw_text,
        captured_on=body.captured_on,
        ocr_confidence=body.ocr_confidence,
        supplier_hint=body.supplier_hint,
    )

    committed = False
    if body.commit:
        # Confident rows are applied; flagged ones are returned for review
        # rather than blocking the whole receipt (TC-O02).
        for line in result.lines:
            if line.needs_review or not line.sku_name or not line.qty:
                continue
            _apply_receipt_line(db, vendor, line)
        db.commit()
        committed = True

    return OcrEntryOut(
        supplier=result.supplier,
        captured_on=result.captured_on,
        stated_total=result.stated_total,
        computed_total=result.computed_total,
        total_matches=result.total_matches,
        overall_confidence=result.overall_confidence,
        review_count=result.review_count,
        lines=[
            ReceiptLineOut(
                raw=l.raw,
                sku_name=l.sku_name,
                qty=l.qty,
                unit=l.unit,
                rate=l.rate,
                amount=l.amount,
                category=l.category,
                shelf_life_days=l.shelf_life_days,
                expires_on=l.expires_on,
                confidence=l.confidence,
                needs_review=l.needs_review,
                issues=l.issues,
            )
            for l in result.lines
        ],
        committed=committed,
    )


def _apply_receipt_line(db: Session, vendor: Vendor, line) -> None:
    item = db.scalar(
        select(InventoryItem).where(
            InventoryItem.vendor_id == vendor.id,
            InventoryItem.sku_name == line.sku_name,
        )
    )
    if item is None:
        item = InventoryItem(
            vendor_id=vendor.id,
            sku_name=line.sku_name,
            category=line.category or "staples",
            unit=line.unit or "pc",
            current_qty=0,
            unit_cost=line.rate or 0,
        )
        db.add(item)
        db.flush()

    item.current_qty += line.qty
    if line.rate:
        item.unit_cost = line.rate
    if line.shelf_life_days:
        item.shelf_life_days = line.shelf_life_days
        item.expires_on = utcnow() + timedelta(days=line.shelf_life_days)
    item.last_updated = utcnow()

    db.add(
        Transaction(
            vendor_id=vendor.id,
            item_id=item.id,
            type="restock",
            qty=line.qty,
            unit_value=line.rate or 0,
            source="ocr",
            confidence=line.confidence,
            raw_text=line.raw[:500],
            occurred_at=utcnow(),
        )
    )
