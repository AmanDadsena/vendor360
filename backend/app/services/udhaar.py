"""The customer credit book: balances, ages and statements.

Two rules carry this module, and both are borrowed from the ledger the
product already has (`ordering.summarise_ledger`), because two khatas in one
app that settle money differently is a bug nobody can see:

1. A balance is derived, never stored.
2. A payment settles the **oldest** debt first. That is the conventional
   treatment, and it is the one that flatters the shop least: it keeps the
   reported age of a debt honest instead of letting a part-payment reset the
   clock on the oldest charge.

Everything here is scoped to one vendor. A customer belongs to a shop, not to
the platform.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.db import utcnow
from ..models import Customer, UdhaarEntry, Vendor

UDHAAR_KINDS = ("credit", "payment")

#: A debt older than this is worth chasing before the others.
STALE_AFTER_DAYS = 30


@dataclass(frozen=True)
class CustomerBalance:
    """What one customer owes, and how long the oldest unpaid part has stood."""

    customer: Customer
    owed: float
    oldest_on: datetime | None

    @property
    def days_outstanding(self) -> int:
        if self.oldest_on is None:
            return 0
        return max(0, (utcnow() - _aware(self.oldest_on)).days)

    @property
    def is_stale(self) -> bool:
        return self.days_outstanding >= STALE_AFTER_DAYS


@dataclass(frozen=True)
class Statement:
    """One customer's page, newest first, with what they owe now."""

    customer: Customer
    owed: float
    entries: list[UdhaarEntry]
    oldest_on: datetime | None


@dataclass(frozen=True)
class Totals:
    """The shop's whole book in three numbers."""

    outstanding: float
    customers: int
    oldest_days: int


def _aware(moment: datetime) -> datetime:
    """SQLite hands back naive datetimes; compare them in UTC."""
    if moment.tzinfo is None:
        return moment.replace(tzinfo=utcnow().tzinfo)
    return moment


def record(
    db: Session,
    vendor: Vendor,
    customer: Customer,
    kind: str,
    amount: float,
    *,
    note: str | None = None,
    transaction_id: uuid.UUID | None = None,
    occurred_at: datetime | None = None,
) -> UdhaarEntry:
    """Write one line of the book.

    Rejects a non-positive amount rather than storing it: direction belongs to
    `kind`, and a negative "credit" would quietly become a payment that no
    screen could explain.
    """
    if kind not in UDHAAR_KINDS:
        raise ValueError(f"kind must be one of {UDHAAR_KINDS}, got {kind!r}")
    if amount <= 0:
        raise ValueError("amount must be positive; direction is carried by kind")
    if customer.vendor_id != vendor.id:
        raise ValueError("customer belongs to another shop")

    entry = UdhaarEntry(
        vendor_id=vendor.id,
        customer_id=customer.id,
        kind=kind,
        amount=float(amount),
        note=note,
        transaction_id=transaction_id,
        occurred_at=occurred_at or utcnow(),
    )
    db.add(entry)
    db.flush()
    return entry


def _settle(entries: list[UdhaarEntry]) -> tuple[float, datetime | None]:
    """Apply payments to charges oldest-first.

    Returns what is still owed and the date of the oldest charge still
    carrying any of it — the age a shopkeeper should act on.
    """
    charges = sorted(
        (e for e in entries if e.kind == "credit"),
        key=lambda e: _aware(e.occurred_at),
    )
    paid = sum(e.amount for e in entries if e.kind == "payment")

    remaining: list[tuple[datetime, float]] = []
    for charge in charges:
        outstanding = charge.amount
        if paid > 0:
            applied = min(paid, outstanding)
            paid -= applied
            outstanding -= applied
        if outstanding > 0.0001:
            remaining.append((_aware(charge.occurred_at), outstanding))

    owed = round(sum(amount for _, amount in remaining), 2)
    oldest = remaining[0][0] if remaining else None

    # Overpayment is credit in hand, not a debt: report zero rather than a
    # negative balance, which would read as the shop owing its customer.
    return (owed if owed > 0 else 0.0), oldest


def balances(db: Session, vendor: Vendor) -> list[CustomerBalance]:
    """Every customer who still owes something, oldest debt first.

    Oldest first, not largest: the debt to chase is the one that has been
    standing longest, and sorting by size buries a six-month-old ₹200 under
    yesterday's ₹2,000.
    """
    rows = db.scalars(
        select(Customer).where(Customer.vendor_id == vendor.id)
    ).all()

    out: list[CustomerBalance] = []
    for customer in rows:
        entries = db.scalars(
            select(UdhaarEntry).where(UdhaarEntry.customer_id == customer.id)
        ).all()
        owed, oldest = _settle(list(entries))
        if owed <= 0:
            continue
        out.append(CustomerBalance(customer=customer, owed=owed, oldest_on=oldest))

    out.sort(key=lambda b: (_aware(b.oldest_on) if b.oldest_on else utcnow()))
    return out


def statement(db: Session, vendor: Vendor, customer: Customer) -> Statement:
    """One customer's entries, newest first, with what they owe now."""
    entries = list(
        db.scalars(
            select(UdhaarEntry)
            .where(UdhaarEntry.customer_id == customer.id)
            .order_by(UdhaarEntry.occurred_at.desc())
        ).all()
    )
    owed, oldest = _settle(entries)
    return Statement(customer=customer, owed=owed, entries=entries, oldest_on=oldest)


def totals(db: Session, vendor: Vendor) -> Totals:
    """The whole book: what is out, with how many people, and how old."""
    rows = balances(db, vendor)
    return Totals(
        outstanding=round(sum(b.owed for b in rows), 2),
        customers=len(rows),
        oldest_days=max((b.days_outstanding for b in rows), default=0),
    )


def day_movement(
    db: Session, vendor: Vendor, start: datetime, end: datetime
) -> tuple[float, float]:
    """How much went out on credit and how much came back, in a window.

    Used by the day close, which asks a different question from the book: not
    "what is owed" but "what moved today".
    """
    entries = db.scalars(
        select(UdhaarEntry).where(
            UdhaarEntry.vendor_id == vendor.id,
            UdhaarEntry.occurred_at >= start,
            UdhaarEntry.occurred_at < end,
        )
    ).all()
    given = sum(e.amount for e in entries if e.kind == "credit")
    collected = sum(e.amount for e in entries if e.kind == "payment")
    return round(given, 2), round(collected, 2)
