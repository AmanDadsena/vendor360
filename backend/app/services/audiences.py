"""Who is entitled to hear about a shop's activity.

Split from `event_bus.py` on purpose. The bus knows how to deliver; this knows
who may receive — and that second question is the consent model, not a routing
detail. Keeping them apart means the privacy rule lives in one readable file
with its own tests, rather than being a filter buried in a delivery loop.

The rule is the same one `distributor_intel.demand_outlook` applies, and it has
to be, because a push channel that skipped it would hand a distributor in real
time exactly what the pull path spends effort withholding.
"""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import VendorDistributor
from .event_bus import Audience


def for_vendor_activity(
    db: Session,
    *,
    vendor_id: uuid.UUID,
    category: str,
) -> Audience:
    """The shop itself, plus every distributor it has consented to.

    Three conditions, all of which `demand_outlook` also applies:

    * the connection is `active` — a paused or ended relationship hears nothing
    * `shares_demand` is true — "order from you, but you do not see me" is a
      position the product supports, and a live channel must honour it
    * the frozen `scope_categories` cover this SKU's category — so a grain
      wholesaler learns nothing when the shop runs out of milk

    The scope is read from the connection row rather than recomputed from the
    distributor's current catalogue, which is the whole point of freezing it:
    adding dairy to a price list tomorrow must not retroactively widen what
    they were told yesterday.
    """
    links = db.scalars(
        select(VendorDistributor).where(
            VendorDistributor.vendor_id == vendor_id,
            VendorDistributor.status == "active",
            VendorDistributor.shares_demand.is_(True),
        )
    ).all()

    entitled = {
        link.supplier_id for link in links if link.covers(category)
    }

    return Audience(
        vendor_ids=frozenset({vendor_id}),
        supplier_ids=frozenset(entitled),
    )


def for_order(
    *, vendor_id: uuid.UUID, supplier_id: uuid.UUID
) -> Audience:
    """Both sides of an order.

    No consent check: an order is a transaction between two parties who have
    already agreed to it. A distributor is entitled to know about the order
    placed with them whatever the shop shares otherwise.
    """
    return Audience(
        vendor_ids=frozenset({vendor_id}),
        supplier_ids=frozenset({supplier_id}),
    )


def for_locality_surge(
    db: Session,
    *,
    vendor_ids: set[uuid.UUID],
    category: str,
) -> Audience:
    """Every shop in a forming pool, and the distributors they each consented to.

    Union of the per-shop audiences rather than a broadcast to the locality: a
    shop that withheld consent contributes to the pool without its distributors
    being told it is short.
    """
    vendors: set[uuid.UUID] = set()
    suppliers: set[uuid.UUID] = set()

    for vendor_id in vendor_ids:
        audience = for_vendor_activity(db, vendor_id=vendor_id, category=category)
        vendors |= audience.vendor_ids
        suppliers |= audience.supplier_ids

    return Audience(vendor_ids=frozenset(vendors), supplier_ids=frozenset(suppliers))


def anonymous() -> Audience:
    """For data already safe for any authenticated principal.

    Currently only heatmap deltas, which carry the same k-anonymity floor the
    heatmap endpoint applies: a cell is emitted only once three stores
    contribute, so no individual shop is recoverable from it.
    """
    return Audience(everyone=True)
