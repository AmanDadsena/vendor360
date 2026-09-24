"""The shop's customer credit book.

Everything here is scoped by `current_vendor`: a customer belongs to one shop,
and a request for a customer the token does not own is a 404 rather than a
403, because saying "that exists, but not for you" is itself a leak about
another shop's book.
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...core.db import get_db
from ...core.security import current_vendor
from ...models import Customer, Vendor
from ...schemas import (
    CustomerIn,
    CustomerOut,
    UdhaarBookOut,
    UdhaarEntryIn,
    UdhaarEntryOut,
    UdhaarRowOut,
    UdhaarStatementOut,
)
from ...services import udhaar

router = APIRouter(prefix="/udhaar", tags=["udhaar"])


def _own_customer(db: Session, vendor: Vendor, customer_id: uuid.UUID) -> Customer:
    customer = db.scalar(
        select(Customer).where(
            Customer.id == customer_id,
            Customer.vendor_id == vendor.id,
        )
    )
    if customer is None:
        raise HTTPException(status_code=404, detail="No such customer")
    return customer


@router.get("", response_model=UdhaarBookOut)
def book(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Who owes the shop, oldest debt first."""
    rows = udhaar.balances(db, vendor)
    totals = udhaar.totals(db, vendor)

    return UdhaarBookOut(
        outstanding=totals.outstanding,
        customers=totals.customers,
        oldest_days=totals.oldest_days,
        rows=[
            UdhaarRowOut(
                customer=CustomerOut.model_validate(row.customer),
                owed=row.owed,
                days_outstanding=row.days_outstanding,
                stale=row.is_stale,
            )
            for row in rows
        ],
    )


@router.post("/customers", response_model=CustomerOut, status_code=201)
def add_customer(
    body: CustomerIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    customer = Customer(
        vendor_id=vendor.id,
        name=body.name.strip(),
        phone=(body.phone or "").strip() or None,
        note=(body.note or "").strip() or None,
    )
    db.add(customer)
    db.commit()
    db.refresh(customer)
    return CustomerOut.model_validate(customer)


@router.get("/{customer_id}", response_model=UdhaarStatementOut)
def statement(
    customer_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    customer = _own_customer(db, vendor, customer_id)
    result = udhaar.statement(db, vendor, customer)

    days = 0
    if result.oldest_on is not None:
        days = next(
            (b.days_outstanding for b in udhaar.balances(db, vendor)
             if b.customer.id == customer.id),
            0,
        )

    return UdhaarStatementOut(
        customer=CustomerOut.model_validate(customer),
        owed=result.owed,
        days_outstanding=days,
        entries=[UdhaarEntryOut.model_validate(e) for e in result.entries],
    )


@router.post("/{customer_id}/entries", response_model=UdhaarStatementOut)
def add_entry(
    customer_id: uuid.UUID,
    body: UdhaarEntryIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Record goods taken on credit, or money returned."""
    customer = _own_customer(db, vendor, customer_id)
    try:
        udhaar.record(db, vendor, customer, body.kind, body.amount, note=body.note)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    db.commit()

    return statement(customer_id=customer.id, vendor=vendor, db=db)
