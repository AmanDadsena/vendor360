"""Paper versions of what the screens show.

Printed in the app's own world: a flat teal band across the head, ink small
print, ruled panels, figures right-aligned. A report that looks like a
different product would not read as the shop's own.

One rule matters more than the look. A PDF outlives the screen it came from
and gets handed to people who cannot ask it questions, so every figure states
its window and a provisional score says so **on the page**. An unlabelled
estimate on something that looks official is exactly where a number does harm.
"""
from __future__ import annotations

import io
from datetime import date, datetime, timezone

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas as pdf_canvas
from sqlalchemy.orm import Session

from ..models import Vendor
from .day_close import DaySummary

# The printed-pack palette, as ink on paper.
TEAL = colors.HexColor("#0B7768")
INK = colors.HexColor("#10201C")
INK_MUTED = colors.HexColor("#475853")
RULE = colors.HexColor("#D5DEDA")
PAPER = colors.white

PAGE_W, PAGE_H = A4
MARGIN = 18 * mm


def _rupees(value: float) -> str:
    """Indian grouping, without relying on a locale being installed."""
    whole = f"{abs(value):,.0f}"
    if abs(value) >= 1000:
        digits = f"{abs(value):.0f}"
        head, tail = digits[:-3], digits[-3:]
        groups = []
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        if head:
            groups.insert(0, head)
        whole = ",".join(groups + [tail])
    sign = "-" if value < 0 else ""
    return f"{sign}Rs {whole}"


class _Sheet:
    """A page with the app's band, a cursor, and the few marks it needs."""

    def __init__(self, title: str, subtitle: str):
        self.buffer = io.BytesIO()
        self.c = pdf_canvas.Canvas(self.buffer, pagesize=A4)
        self.c.setTitle(title)
        self._band(title, subtitle)
        self.y = PAGE_H - 52 * mm

    def _band(self, title: str, subtitle: str) -> None:
        self.c.setFillColor(TEAL)
        self.c.rect(0, PAGE_H - 38 * mm, PAGE_W, 38 * mm, stroke=0, fill=1)
        self.c.setFillColor(PAPER)
        self.c.setFont("Helvetica-Bold", 20)
        self.c.drawString(MARGIN, PAGE_H - 22 * mm, title)
        self.c.setFont("Helvetica", 10)
        self.c.drawString(MARGIN, PAGE_H - 30 * mm, subtitle)

    def heading(self, text: str) -> None:
        self.y -= 6 * mm
        self.c.setFillColor(INK)
        self.c.setFont("Helvetica-Bold", 12)
        self.c.drawString(MARGIN, self.y, text)
        self.y -= 3 * mm
        self.rule()

    def rule(self, heavy: bool = False) -> None:
        self.c.setStrokeColor(INK if heavy else RULE)
        self.c.setLineWidth(1.2 if heavy else 0.6)
        self.c.line(MARGIN, self.y, PAGE_W - MARGIN, self.y)
        self.y -= 6 * mm

    def line(self, label: str, value: str, *, strong: bool = False) -> None:
        self.c.setFillColor(INK if strong else INK_MUTED)
        self.c.setFont("Helvetica-Bold" if strong else "Helvetica", 10.5)
        self.c.drawString(MARGIN, self.y, label)
        self.c.setFillColor(INK)
        self.c.setFont("Helvetica-Bold" if strong else "Helvetica", 10.5)
        self.c.drawRightString(PAGE_W - MARGIN, self.y, value)
        self.y -= 6.5 * mm

    def note(self, text: str) -> None:
        self.c.setFillColor(INK_MUTED)
        self.c.setFont("Helvetica", 8.5)
        for chunk in _wrap(text, 108):
            self.c.drawString(MARGIN, self.y, chunk)
            self.y -= 4.4 * mm
        self.y -= 2 * mm

    def finish(self, footer: str) -> bytes:
        self.c.setFillColor(INK_MUTED)
        self.c.setFont("Helvetica", 8)
        self.c.drawString(MARGIN, 14 * mm, footer)
        self.c.showPage()
        self.c.save()
        return self.buffer.getvalue()


def _wrap(text: str, width: int) -> list[str]:
    words, lines, current = text.split(), [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if len(candidate) > width:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines


def day_sheet_pdf(vendor: Vendor, summary: DaySummary) -> bytes:
    """One page: what the day came to."""
    sheet = _Sheet(
        "Day close",
        f"{vendor.store_name} · {summary.on.strftime('%d %B %Y')}",
    )

    sheet.heading("Money")
    sheet.line("Sales", _rupees(summary.sales_value), strong=True)
    sheet.line("Entries", str(summary.transaction_count))
    sheet.line("Given on udhaar", _rupees(summary.udhaar_given))
    sheet.line("Collected on udhaar", _rupees(summary.udhaar_collected))
    sheet.rule(heavy=True)
    sheet.line("Cash in", _rupees(summary.cash_in), strong=True)
    sheet.note(
        "Cash in is sales less what went out on the book, plus what came back. "
        "A sale recorded on credit is revenue, but it is not money in the "
        "drawer today."
    )

    if summary.top_items:
        sheet.heading("Sold most")
        for item in summary.top_items:
            qty = f"{item.qty:.0f}" if item.qty == int(item.qty) else f"{item.qty:.1f}"
            sheet.line(f"{item.sku_name}  ({qty} {item.unit})", _rupees(item.value))

    sheet.heading("Stock")
    sheet.line("Restocked", _rupees(summary.restock_value))
    sheet.line("Wasted", _rupees(summary.wastage_value))
    sheet.line("Below reorder point", str(summary.low_stock_count))

    return sheet.finish(
        "Vendor360 · figures for the shop's own day (07:00-21:00 IST), from its "
        "recorded entries."
    )


def credit_report_pdf(db: Session, vendor: Vendor) -> bytes:
    """The credit assessment, as a page a lender can keep.

    Rendered from the same service the screen reads, so the paper and the app
    cannot disagree.
    """
    from ..api.routes.intelligence import _score_inputs
    from ..services.health_score import compute_health_score

    score = compute_health_score(**_score_inputs(db, vendor.id))
    components = {c.key: c for c in score.components}
    generated = datetime.now(timezone.utc).strftime("%d %B %Y")

    sheet = _Sheet(
        "Credit assessment",
        f"{vendor.store_name} · {vendor.locality or 'Pune'} · {generated}",
    )

    sheet.heading("Score")
    sheet.line("Operational health", f"{score.score:.1f} / 100", strong=True)
    sheet.line("Band", score.band.replace("_", " ").title())
    sheet.line("History", f"{score.days_of_history} days of recorded activity")

    if score.provisional:
        # Said on the page, not only in the app. A PDF is read by people who
        # cannot ask it how sure it is.
        sheet.note(
            "PROVISIONAL. This score is built on fewer than 90 days of "
            "activity and will move as more is recorded. It is an operational "
            "record, not a credit bureau rating."
        )

    sheet.heading("How it is made up")
    for key, label in (
        ("consistency", "Sales consistency"),
        ("turnover", "Inventory turnover"),
        ("waste", "Waste control"),
    ):
        component = components.get(key)
        if component is None:
            continue
        sheet.line(
            f"{label} — {component.detail}",
            f"{component.value:.0f} x {component.weight:.2f} = "
            f"{component.contribution:.1f}",
        )
    sheet.rule(heavy=True)
    sheet.line("Total", f"{score.score:.1f}", strong=True)

    sheet.heading("What this is")
    sheet.note(
        "Every figure comes from this shop's own recorded sales, restocks and "
        "wastage over the period stated above. Nothing is inferred from other "
        "shops, and no external data is used. The shop shares this with a "
        "lender by its own choice, one lender at a time."
    )

    return sheet.finish(
        f"Vendor360 · generated {generated} · {vendor.store_name} · "
        f"{vendor.phone}"
    )
