"""Setup: the master catalogue and bulk item creation.

Unauthenticated for the catalogue itself — it is a static product list with
nothing private in it, and the onboarding screen needs it before a shop has
finished signing in.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ...core.db import get_db
from ...core.security import current_vendor
from ...models import Vendor
from ...schemas import ItemOut, MasterSkuOut, QuickAddIn, QuickAddOut
from ...services.onboarding import (
    master_catalog,
    quick_add,
    suggested_for_categories,
)

router = APIRouter(prefix="/onboarding", tags=["onboarding"])


def _out(sku) -> MasterSkuOut:
    return MasterSkuOut(
        key=sku.key,
        name_en=sku.name_en,
        name_hi=sku.name_hi,
        name_mr=sku.name_mr,
        category=sku.category,
        unit=sku.unit,
        typical_pack=sku.typical_pack,
        typical_price=sku.typical_price,
        popularity=sku.popularity,
    )


@router.get("/master-catalog", response_model=list[MasterSkuOut])
def catalog(
    category: str | None = None,
    categories: str | None = Query(
        None, description="Comma-separated aisles, for the setup flow"
    ),
    limit: int | None = None,
):
    """The starter list a shop taps instead of typing.

    `categories` returns a short, ranked slice per aisle — what the setup flow
    shows after someone picks what they sell. `category` and `limit` serve the
    full browsable list behind search.
    """
    if categories:
        keys = [c.strip() for c in categories.split(",") if c.strip()]
        return [_out(s) for s in suggested_for_categories(keys)]

    return [_out(s) for s in master_catalog(category=category, limit=limit)]


@router.post("/quick-add", response_model=QuickAddOut)
def add_items(
    body: QuickAddIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Create inventory rows from a handful of taps."""
    result = quick_add(db, vendor, body.keys)
    db.commit()

    return QuickAddOut(
        created=len(result.created),
        skipped=result.skipped,
        items=[ItemOut.model_validate(i) for i in result.created],
    )
