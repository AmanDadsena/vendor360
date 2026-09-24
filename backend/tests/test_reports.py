"""The day close and the things a shopkeeper can hand to someone else (TC-R**).

A PDF outlives the screen it came from, so these check what is *said* on the
page as well as that a page comes back at all.
"""
from __future__ import annotations

import re
import uuid
import zipfile
from datetime import timedelta
from io import BytesIO

import pytest

from app.core.db import utcnow
from app.models import Customer, Transaction
from app.services import day_close, udhaar


@pytest.fixture()
def customer(db, vendor):
    c = Customer(vendor_id=vendor.id, name="Suresh", phone="9876500099")
    db.add(c)
    db.commit()
    return c


def sale(db, vendor, item, qty, value, *, when=None, kind="sale"):
    db.add(
        Transaction(
            vendor_id=vendor.id,
            item_id=item.id,
            type=kind,
            qty=qty,
            unit_value=value,
            source="manual",
            occurred_at=when or utcnow(),
        )
    )
    db.commit()


def pdf_text(blob: bytes) -> str:
    """Enough of a PDF's text to assert on, without a parser dependency.

    reportlab writes each page's content stream ASCII85-encoded and then
    deflated, so this undoes both and pulls the strings out of the
    text-showing operators.
    """
    import base64
    import zlib

    out: list[str] = []
    for match in re.finditer(rb"stream\r?\n(.*?)endstream", blob, re.S):
        chunk = match.group(1).strip()
        for decode in (
            lambda c: zlib.decompress(base64.a85decode(c, adobe=True)),
            zlib.decompress,
            lambda c: c,
        ):
            try:
                chunk = decode(chunk)
                break
            except Exception:  # noqa: BLE001 - try the next encoding
                continue
        out.extend(
            m.group(1).decode("latin-1")
            for m in re.finditer(rb"\((.*?)\)\s*Tj", chunk)
        )
    return " ".join(out)


# --------------------------------------------------------- TC-R01 day close
def test_tc_r01_a_day_adds_up_its_own_sales(db, vendor, milk):
    sale(db, vendor, milk, 10, 28)
    sale(db, vendor, milk, 5, 28)

    summary = day_close.summarise_day(db, vendor, day_close.shop_today())

    assert summary.sales_value == 420
    assert summary.transaction_count == 2
    assert summary.top_items[0].sku_name == "Milk"


def test_tc_r01_a_quiet_day_reports_zeroes_not_an_error(db, vendor, milk):
    summary = day_close.summarise_day(db, vendor, day_close.shop_today())

    assert summary.sales_value == 0
    assert summary.transaction_count == 0
    assert summary.top_items == []


def test_tc_r01_yesterdays_sales_stay_in_yesterday(db, vendor, milk):
    sale(db, vendor, milk, 10, 28, when=utcnow() - timedelta(days=1))

    today = day_close.summarise_day(db, vendor, day_close.shop_today())
    assert today.sales_value == 0


def test_tc_r02_the_window_is_the_shops_day_not_utcs(db, vendor):
    """Pune runs at UTC+5:30, so a UTC boundary would cut the day at 5:30am."""
    on = day_close.shop_today()
    start, end = day_close.shop_day_window(on)

    assert (end - start) == timedelta(days=1)
    # Midnight in the shop is 18:30 UTC the day before.
    assert start.hour == 18 and start.minute == 30


def test_tc_r02_waste_and_restock_are_not_sales(db, vendor, milk):
    sale(db, vendor, milk, 10, 28)
    sale(db, vendor, milk, 2, 24, kind="wastage")
    sale(db, vendor, milk, 20, 24, kind="restock")

    summary = day_close.summarise_day(db, vendor, day_close.shop_today())

    assert summary.sales_value == 280
    assert summary.wastage_value == 48
    assert summary.restock_value == 480


def test_tc_r03_cash_in_is_not_the_same_as_sales(db, vendor, milk, customer):
    """A sale on credit is revenue, not money in the drawer."""
    sale(db, vendor, milk, 10, 28)
    udhaar.record(db, vendor, customer, "credit", 200)
    udhaar.record(db, vendor, customer, "payment", 50)
    db.commit()

    summary = day_close.summarise_day(db, vendor, day_close.shop_today())

    assert summary.sales_value == 280
    assert summary.udhaar_given == 200
    assert summary.udhaar_collected == 50
    assert summary.cash_in == 130


# -------------------------------------------------------- TC-R04 the series
def test_tc_r04_a_closed_day_is_a_zero_not_a_gap(db, vendor, milk):
    sale(db, vendor, milk, 10, 28)

    series = day_close.sales_series(db, vendor, days=14)

    # Fourteen points for a fourteen-day window: a chart that silently drops a
    # closed day draws a trend that never happened.
    assert len(series) == 14
    assert series[-1][1] == 280
    assert series[0][1] == 0
    # Oldest first.
    assert series[0][0] < series[-1][0]


# ---------------------------------------------------------- TC-R05 the PDFs
def test_tc_r05_the_day_sheet_is_a_pdf(client_vendor):
    response = client_vendor.get("/reports/day-close.pdf")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"
    assert response.content.startswith(b"%PDF")
    assert "attachment" in response.headers["content-disposition"]


def test_tc_r05_the_day_sheet_names_the_shop_and_the_day(client_vendor, vendor):
    text = pdf_text(client_vendor.get("/reports/day-close.pdf").content)

    assert vendor.store_name in text
    assert "Day close" in text
    assert "Cash in" in text


def test_tc_r06_a_provisional_score_says_so_on_the_page(client_vendor):
    """A PDF is read by people who cannot ask it how sure it is."""
    text = pdf_text(client_vendor.get("/reports/credit.pdf").content)

    assert "Credit assessment" in text
    # The seeded test vendor has almost no history, so this must be labelled.
    assert "PROVISIONAL" in text.upper()
    assert "not a credit bureau rating" in text


def test_tc_r06_the_credit_report_says_where_its_figures_came_from(client_vendor):
    text = pdf_text(client_vendor.get("/reports/credit.pdf").content)

    assert "own recorded sales" in text
    assert "no external data" in text.lower()


# --------------------------------------------------------- TC-R07 the sheet
def test_tc_r07_the_ledger_is_a_real_workbook(client_vendor):
    response = client_vendor.get("/reports/ledger.xlsx")

    assert response.status_code == 200
    assert "spreadsheetml" in response.headers["content-type"]
    # A valid xlsx is a zip; a truncated one is not.
    with zipfile.ZipFile(BytesIO(response.content)) as book:
        assert "xl/workbook.xml" in book.namelist()


def test_tc_r07_the_workbook_has_a_sheet_per_question(client_vendor):
    from openpyxl import load_workbook

    blob = client_vendor.get("/reports/ledger.xlsx").content
    book = load_workbook(BytesIO(blob))

    assert book.sheetnames == ["Sales", "Stock", "Udhaar"]


def test_tc_r07_amounts_are_numbers_not_text(client_vendor, db, vendor, milk):
    """A workbook whose figures cannot be summed is a screenshot."""
    from openpyxl import load_workbook

    sale(db, vendor, milk, 10, 28)
    blob = client_vendor.get("/reports/ledger.xlsx").content
    sheet = load_workbook(BytesIO(blob))["Sales"]

    value = sheet.cell(row=2, column=7).value
    assert isinstance(value, (int, float))
    assert value == 280


# ---------------------------------------------------------- TC-R08 scoping
def test_tc_r08_reports_need_a_vendor_token(api, client_dist):
    assert api.get("/reports/day-close").status_code in (401, 403)
    assert client_dist.get("/reports/day-close.pdf").status_code == 403


def test_tc_r08_the_day_close_reads_over_the_api(client_vendor, db, vendor, milk):
    sale(db, vendor, milk, 4, 28)

    body = client_vendor.get("/reports/day-close").json()

    assert body["sales_value"] == 112
    assert body["top_items"][0]["sku_name"] == "Milk"
    assert body["on"] == day_close.shop_today().isoformat()
