"""Forming and breaking the trading relationship between a shop and a wholesaler.

Small enough to read in one sitting, and deliberately separate from ordering:
what a distributor is allowed to *see* is a different question from what they
have been asked to *deliver*, and mixing the two is how consent checks end up
getting skipped in the code path that needed them most.
"""
from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.db import utcnow
from ..models import (
    CatalogEntry,
    PurchaseOrder,
    Supplier,
    Vendor,
    VendorDistributor,
)


class ConnectionError_(ValueError):
    """A connection rule was violated. Routes translate this to a 400."""


def catalog_categories(db: Session, supplier_id: uuid.UUID) -> list[str]:
    """The aisles this distributor currently sells into."""
    rows = db.scalars(
        select(CatalogEntry.category)
        .where(
            CatalogEntry.supplier_id == supplier_id,
            CatalogEntry.active.is_(True),
        )
        .distinct()
    ).all()
    return sorted(set(rows))


def connect(
    db: Session,
    *,
    vendor: Vendor,
    supplier: Supplier,
    shares_demand: bool = True,
    credit_terms_days: int = 0,
) -> VendorDistributor:
    """Open a trading relationship, freezing the consent scope as it stands.

    The freeze is the point. Scope is snapshotted from the distributor's
    catalogue *at this moment*, so a grain wholesaler who later adds dairy to
    their price list does not thereby acquire visibility into this shop's milk
    numbers. Widening requires calling this again, which is an act the vendor
    performs knowingly.

    Re-connecting an existing relationship re-grants it on today's terms rather
    than creating a second row, so the unique pair constraint holds and the
    history stays in one place.
    """
    scope = catalog_categories(db, supplier.id)

    existing = db.scalar(
        select(VendorDistributor).where(
            VendorDistributor.vendor_id == vendor.id,
            VendorDistributor.supplier_id == supplier.id,
        )
    )

    if existing is not None:
        existing.status = "active"
        existing.shares_demand = shares_demand
        existing.scope_categories = scope
        existing.credit_terms_days = credit_terms_days
        existing.connected_at = utcnow()
        existing.revoked_at = None
        db.flush()
        return existing

    link = VendorDistributor(
        vendor_id=vendor.id,
        supplier_id=supplier.id,
        status="active",
        shares_demand=shares_demand,
        scope_categories=scope,
        credit_terms_days=credit_terms_days,
    )
    db.add(link)
    db.flush()
    return link


def disconnect(
    db: Session, *, vendor: Vendor, supplier_id: uuid.UUID
) -> VendorDistributor:
    """End a relationship without erasing it.

    The row survives so the ledger, the order history and the record of who
    could see what and when all remain answerable. An open order blocks the
    break: walking away from stock already on a van is not something the app
    should let someone do by accident.
    """
    link = db.scalar(
        select(VendorDistributor).where(
            VendorDistributor.vendor_id == vendor.id,
            VendorDistributor.supplier_id == supplier_id,
        )
    )
    if link is None:
        raise ConnectionError_("You are not connected to this distributor")

    open_orders = db.scalar(
        select(func.count(PurchaseOrder.id)).where(
            PurchaseOrder.vendor_id == vendor.id,
            PurchaseOrder.supplier_id == supplier_id,
            PurchaseOrder.status.in_(("placed", "confirmed", "dispatched")),
        )
    )
    if open_orders:
        raise ConnectionError_(
            f"{open_orders} order{'s are' if open_orders > 1 else ' is'} still "
            "open with this distributor. Receive or cancel "
            f"{'them' if open_orders > 1 else 'it'} first."
        )

    link.status = "ended"
    link.shares_demand = False
    link.revoked_at = utcnow()
    db.flush()
    return link
