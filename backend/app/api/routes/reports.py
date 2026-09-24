"""Reports a shopkeeper can hand to somebody else.

A day sheet, a lender's credit report, and the ledger as a workbook. Three
things the app could describe on a screen but could not, until now, put on
paper — which is what an accountant, a lender or a family member asking "how
is the shop doing" actually wants.

Every figure is the server's own; nothing here recomputes anything a screen
already computes differently.
"""
from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy.orm import Session

from ...core.db import get_db
from ...core.security import current_vendor
from ...models import Vendor
from ...schemas import DayCloseOut, SalesPointOut, SoldItemOut
from ...services import day_close
from ...services.render_pdf import credit_report_pdf, day_sheet_pdf
from ...services.render_xlsx import ledger_workbook

router = APIRouter(prefix="/reports", tags=["reports"])


def _summary(db: Session, vendor: Vendor, on: date | None) -> day_close.DaySummary:
    return day_close.summarise_day(db, vendor, on or day_close.shop_today())


@router.get("/day-close", response_model=DayCloseOut)
def day_close_json(
    on: date | None = Query(default=None),
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """What the day came to, in the shop's own clock."""
    summary = _summary(db, vendor, on)

    return DayCloseOut(
        on=summary.on,
        sales_value=summary.sales_value,
        transaction_count=summary.transaction_count,
        cash_in=summary.cash_in,
        wastage_value=summary.wastage_value,
        restock_value=summary.restock_value,
        udhaar_given=summary.udhaar_given,
        udhaar_collected=summary.udhaar_collected,
        low_stock_count=summary.low_stock_count,
        top_items=[
            SoldItemOut(
                sku_name=i.sku_name, qty=i.qty, unit=i.unit, value=i.value
            )
            for i in summary.top_items
        ],
    )


@router.get("/sales-series", response_model=list[SalesPointOut])
def sales_series(
    days: int = Query(default=14, ge=2, le=90),
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Daily takings, oldest first, with closed days present as zeroes."""
    return [
        SalesPointOut(on=on, value=value, count=count)
        for on, value, count in day_close.sales_series(db, vendor, days)
    ]


def _attachment(content: bytes, media_type: str, filename: str) -> Response:
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/day-close.pdf")
def day_close_pdf(
    on: date | None = Query(default=None),
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    summary = _summary(db, vendor, on)
    return _attachment(
        day_sheet_pdf(vendor, summary),
        "application/pdf",
        f"day-close-{summary.on.isoformat()}.pdf",
    )


@router.get("/credit.pdf")
def credit_pdf(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """The credit assessment as a page a lender can keep."""
    return _attachment(
        credit_report_pdf(db, vendor),
        "application/pdf",
        f"credit-report-{date.today().isoformat()}.pdf",
    )


@router.get("/ledger.xlsx")
def ledger_xlsx(
    days: int = Query(default=90, ge=1, le=365),
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Sales, stock and the credit book, as three sheets."""
    return _attachment(
        ledger_workbook(db, vendor, days=days),
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        f"vendor360-ledger-{date.today().isoformat()}.xlsx",
    )
