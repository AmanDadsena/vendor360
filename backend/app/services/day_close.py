"""What the day came to.

The last question a shopkeeper asks, and the first a lender asks about a
shop: money in, what moved, what was lost, what went out on credit and what
came back.

The window is the **shop's** day, not UTC's. Pune runs at UTC+5:30, so a UTC
day boundary cuts the shop's day at 5:30am — which happens to be harmless
while the shutters are down, and would be wrong the moment anyone logs an
early delivery or the app is used anywhere east of here. `detectors` already
holds the offset for exactly this reason; this uses the same one rather than
inventing a second clock.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import InventoryItem, Transaction, Vendor
from . import udhaar as udhaar_service
from .detectors import SHOP_UTC_OFFSET_HOURS

SHOP_OFFSET = timedelta(hours=SHOP_UTC_OFFSET_HOURS)


@dataclass(frozen=True)
class SoldItem:
    sku_name: str
    qty: float
    unit: str
    value: float


@dataclass(frozen=True)
class DaySummary:
    """One day, closed."""

    on: date
    sales_value: float
    transaction_count: int
    top_items: list[SoldItem] = field(default_factory=list)
    wastage_value: float = 0.0
    restock_value: float = 0.0
    udhaar_given: float = 0.0
    udhaar_collected: float = 0.0
    low_stock_count: int = 0

    @property
    def cash_in(self) -> float:
        """Sales less what went out on the book.

        A sale recorded on credit is revenue, but it is not money in the
        drawer, and a day sheet that conflates the two tells a shopkeeper
        they had a better day than they did.
        """
        return round(self.sales_value - self.udhaar_given + self.udhaar_collected, 2)


def shop_day_window(on: date) -> tuple[datetime, datetime]:
    """The UTC instants that bound a shop's calendar day."""
    start_local = datetime(on.year, on.month, on.day, tzinfo=timezone.utc)
    start = start_local - SHOP_OFFSET
    return start, start + timedelta(days=1)


def shop_today() -> date:
    """Today, as the shop counts it."""
    return (datetime.now(timezone.utc) + SHOP_OFFSET).date()


def summarise_day(db: Session, vendor: Vendor, on: date) -> DaySummary:
    start, end = shop_day_window(on)

    rows = db.scalars(
        select(Transaction).where(
            Transaction.vendor_id == vendor.id,
            Transaction.occurred_at >= start,
            Transaction.occurred_at < end,
        )
    ).all()

    sales = [t for t in rows if t.type == "sale"]
    wastage = [t for t in rows if t.type == "wastage"]
    restocks = [t for t in rows if t.type == "restock"]

    by_item: dict[str, SoldItem] = {}
    names = {
        item.id: (item.sku_name, item.unit)
        for item in db.scalars(
            select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
        )
    }
    for sale in sales:
        sku_name, unit = names.get(sale.item_id, ("Unknown", ""))
        existing = by_item.get(sku_name)
        value = sale.qty * (sale.unit_value or 0)
        if existing is None:
            by_item[sku_name] = SoldItem(sku_name, sale.qty, unit, value)
        else:
            by_item[sku_name] = SoldItem(
                sku_name, existing.qty + sale.qty, unit, existing.value + value
            )

    top = sorted(by_item.values(), key=lambda i: -i.value)[:5]

    given, collected = udhaar_service.day_movement(db, vendor, start, end)

    low = db.scalar(
        select(func.count(InventoryItem.id)).where(
            InventoryItem.vendor_id == vendor.id,
            InventoryItem.current_qty <= InventoryItem.reorder_point,
        )
    )

    return DaySummary(
        on=on,
        sales_value=round(sum(t.qty * (t.unit_value or 0) for t in sales), 2),
        transaction_count=len(sales),
        top_items=top,
        wastage_value=round(sum(t.qty * (t.unit_value or 0) for t in wastage), 2),
        restock_value=round(sum(t.qty * (t.unit_value or 0) for t in restocks), 2),
        udhaar_given=given,
        udhaar_collected=collected,
        low_stock_count=int(low or 0),
    )


def sales_series(db: Session, vendor: Vendor, days: int = 14) -> list[tuple[date, float, int]]:
    """Daily takings for the last `days` shop-days, oldest first.

    Days with no sales are present as zeroes rather than missing: a chart that
    silently drops a closed day draws a trend that never happened.
    """
    today = shop_today()
    out: list[tuple[date, float, int]] = []

    for step in range(days - 1, -1, -1):
        on = today - timedelta(days=step)
        start, end = shop_day_window(on)
        value = db.scalar(
            select(
                func.coalesce(func.sum(Transaction.qty * Transaction.unit_value), 0.0)
            ).where(
                Transaction.vendor_id == vendor.id,
                Transaction.type == "sale",
                Transaction.occurred_at >= start,
                Transaction.occurred_at < end,
            )
        )
        count = db.scalar(
            select(func.count(Transaction.id)).where(
                Transaction.vendor_id == vendor.id,
                Transaction.type == "sale",
                Transaction.occurred_at >= start,
                Transaction.occurred_at < end,
            )
        )
        out.append((on, round(float(value or 0), 2), int(count or 0)))

    return out
