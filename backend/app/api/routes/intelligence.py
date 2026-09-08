"""Forecast, health score, sync, pools, heatmap, expiry, and dashboard routes."""
from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ...core.db import get_db, utcnow
from ...core.security import current_vendor
from ...models import (
    BargainPool,
    InventoryItem,
    Lender,
    PoolMember,
    ScoreConsent,
    Transaction,
    Vendor,
)
from ...schemas import (
    DashboardOut,
    CreditReportOut,
    ExpiryItemOut,
    ForecastDayOut,
    ForecastOut,
    HeatCellOut,
    HeatmapOut,
    HealthScoreOut,
    ItemOut,
    PoolJoinIn,
    PoolOut,
    ScoreComponentOut,
    SyncBatchIn,
    SyncBatchOut,
    SyncEventResult,
    VendorOut,
)
from ...services import pooling
from ...services.catalog import CATEGORIES
from ...services.forecasting import forecast_item, mape
from ...services.health_score import compute_health_score
from ...services.heatmap import build_heatmap
from ...services.signals import forecast_weather, upcoming_festivals
from ...services.sync import apply_batch
from .inventory import _owned_item, _sales_history

router = APIRouter(tags=["intelligence"])


# ----------------------------------------------------------------- forecast
def _category_daily_mean(db: Session, vendor_id: uuid.UUID, category: str) -> float:
    """Average daily sales across the vendor's items in a category.

    The cold-start basis for a SKU with no history of its own (TC-F04).
    """
    since = utcnow() - timedelta(days=30)
    total = db.scalar(
        select(func.coalesce(func.sum(Transaction.qty), 0.0))
        .join(InventoryItem, InventoryItem.id == Transaction.item_id)
        .where(
            Transaction.vendor_id == vendor_id,
            Transaction.type == "sale",
            Transaction.occurred_at >= since,
            InventoryItem.category == category,
        )
    )
    distinct_items = db.scalar(
        select(func.count(func.distinct(InventoryItem.id))).where(
            InventoryItem.vendor_id == vendor_id, InventoryItem.category == category
        )
    ) or 1
    return float(total) / 30.0 / distinct_items


def _headline(result) -> str:
    """One plain-language sentence a vendor can act on (UI/UX 5.5)."""
    peak = result.peak
    if peak is None:
        return "Not enough data to forecast yet."

    when = peak.on.strftime("%a %d %b")
    if peak.driver and abs(peak.driver_effect) >= 0.08:
        direction = "more" if peak.driver_effect > 0 else "less"
        return (
            f"Stock {abs(peak.driver_effect):.0%} {direction} {result.sku_name.lower()} "
            f"by {when} — {peak.driver}."
        )
    return f"Steady demand: about {peak.predicted:g} units expected on {when}."


@router.get("/forecast/{item_id}", response_model=ForecastOut)
def get_forecast(
    item_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    days: int = Query(7, ge=1, le=30),
):
    item = _owned_item(db, vendor, item_id)
    history = _sales_history(db, item.id)

    result = forecast_item(
        item_id=str(item.id),
        sku_name=item.sku_name,
        category_key=item.category,
        history=history,
        horizon_days=days,
        lat=vendor.lat or 18.52,
        lon=vendor.lon or 73.86,
        category_daily_mean=_category_daily_mean(db, vendor.id, item.category),
    )

    return ForecastOut(
        item_id=item.id,
        sku_name=item.sku_name,
        category=item.category,
        model_version=result.model_version,
        used_fallback=result.used_fallback,
        history_days=result.history_days,
        total_predicted=round(result.total_predicted, 2),
        days=[
            ForecastDayOut(
                on=d.on,
                predicted=d.predicted,
                lower=d.lower,
                upper=d.upper,
                driver=d.driver,
                driver_effect=d.driver_effect,
                baseline=d.baseline,
            )
            for d in result.days
        ],
        headline=_headline(result),
    )


@router.get("/forecast")
def forecast_overview(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    days: int = Query(7, ge=1, le=14),
    limit: int = Query(8, le=30),
):
    """Forecasts for the vendor's most active items, biggest movers first."""
    items = db.scalars(
        select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
    ).all()

    out = []
    for item in items:
        history = _sales_history(db, item.id)
        if not history:
            continue
        result = forecast_item(
            item_id=str(item.id),
            sku_name=item.sku_name,
            category_key=item.category,
            history=history,
            horizon_days=days,
            lat=vendor.lat or 18.52,
            lon=vendor.lon or 73.86,
        )
        peak = result.peak
        out.append(
            {
                "item_id": str(item.id),
                "sku_name": item.sku_name,
                "category": item.category,
                "unit": item.unit,
                "current_qty": item.current_qty,
                "reorder_point": item.reorder_point,
                "total_predicted": round(result.total_predicted, 2),
                "used_fallback": result.used_fallback,
                "headline": _headline(result),
                "peak_driver": peak.driver if peak else None,
                "peak_effect": peak.driver_effect if peak else 0.0,
                "days": [
                    {
                        "on": d.on.isoformat(),
                        "predicted": d.predicted,
                        "lower": d.lower,
                        "upper": d.upper,
                        "driver": d.driver,
                    }
                    for d in result.days
                ],
            }
        )

    # Rank by the strength of the signal, so a festival spike surfaces above a
    # high-volume item with nothing interesting happening.
    out.sort(key=lambda r: (abs(r["peak_effect"]), r["total_predicted"]), reverse=True)
    return out[:limit]


@router.get("/forecast-accuracy")
def forecast_accuracy(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    lookback: int = Query(14, ge=7, le=60),
):
    """Backtest: fit on data before a cutoff, score against what actually sold.

    The Report 5.5 evaluation metric. Refitting on the truncated history rather
    than reusing stored predictions is what makes this an honest out-of-sample
    measure instead of a restatement of the training fit.
    """
    items = db.scalars(
        select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
    ).all()
    cutoff = date.today() - timedelta(days=lookback)

    rows, all_actual, all_pred = [], [], []

    for item in items:
        history = _sales_history(db, item.id, days=180)
        train = [(d, q) for d, q in history if d <= cutoff]
        if len(train) < 30:
            continue

        result = forecast_item(
            item_id=str(item.id),
            sku_name=item.sku_name,
            category_key=item.category,
            history=train,
            horizon_days=lookback,
            today=cutoff,
            lat=vendor.lat or 18.52,
            lon=vendor.lon or 73.86,
        )

        actual_by_day: dict[date, float] = defaultdict(float)
        for d, q in history:
            if d > cutoff:
                actual_by_day[d] += q

        actual = [actual_by_day.get(p.on, 0.0) for p in result.days]
        predicted = [p.predicted for p in result.days]
        item_mape = mape(actual, predicted)
        if item_mape is None:
            continue

        all_actual.extend(actual)
        all_pred.extend(predicted)
        rows.append(
            {
                "item_id": str(item.id),
                "sku_name": item.sku_name,
                "category": item.category,
                "mape": item_mape,
                "actual_total": round(sum(actual), 1),
                "predicted_total": round(sum(predicted), 1),
            }
        )

    rows.sort(key=lambda r: r["mape"])
    return {
        "lookback_days": lookback,
        "cutoff": cutoff.isoformat(),
        "overall_mape": mape(all_actual, all_pred),
        "items_scored": len(rows),
        "items": rows,
    }


# ------------------------------------------------------------- health score
def _score_inputs(db: Session, vendor_id: uuid.UUID, days: int = 90) -> dict:
    window_end = date.today()
    window_start = window_end - timedelta(days=days - 1)
    since = utcnow() - timedelta(days=days)

    rows = db.execute(
        select(Transaction.occurred_at, Transaction.type, Transaction.qty, Transaction.unit_value)
        .where(Transaction.vendor_id == vendor_id, Transaction.occurred_at >= since)
    ).all()

    sale_days, cogs, waste_value, purchase_value = set(), 0.0, 0.0, 0.0
    for occurred, kind, qty, unit_value in rows:
        value = float(qty) * float(unit_value or 0)
        if kind == "sale":
            sale_days.add(occurred.date())
            cogs += value
        elif kind == "wastage":
            waste_value += value
        elif kind == "restock":
            purchase_value += value

    inventory_value = db.scalar(
        select(
            func.coalesce(
                func.sum(InventoryItem.current_qty * InventoryItem.unit_cost), 0.0
            )
        ).where(InventoryItem.vendor_id == vendor_id)
    ) or 0.0

    first_txn = db.scalar(
        select(func.min(Transaction.occurred_at)).where(Transaction.vendor_id == vendor_id)
    )
    if first_txn and first_txn.date() > window_start:
        window_start = first_txn.date()

    # The transaction query uses a timestamp cutoff while the window is a date
    # range, so a transaction just inside the cutoff can fall a day outside the
    # window -- reporting "active 91/90 days", which reads as a bug to anyone
    # looking at their own score. Clamping here keeps the count and the window
    # describing the same period.
    sale_days = {d for d in sale_days if window_start <= d <= window_end}

    return {
        "sale_days": sale_days,
        "window_start": window_start,
        "window_end": window_end,
        "cogs": cogs,
        "avg_inventory_value": float(inventory_value),
        "waste_value": waste_value,
        "purchase_value": purchase_value,
    }


@router.get("/health-score", response_model=HealthScoreOut)
def health_score(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    score = compute_health_score(**_score_inputs(db, vendor.id))

    vendor.health_score = score.score
    vendor.health_score_at = utcnow()
    db.commit()

    return HealthScoreOut(
        score=score.score,
        band=score.band,
        provisional=score.provisional,
        days_of_history=score.days_of_history,
        explanation=score.explanation,
        components=[ScoreComponentOut(**c) for c in score.as_dict["components"]],
    )


@router.get("/health-score/report", response_model=CreditReportOut)
def health_score_report(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    inputs = _score_inputs(db, vendor.id)
    score = compute_health_score(**inputs)

    ninety_days_ago = utcnow() - timedelta(days=90)
    sales_total = db.scalar(
        select(func.coalesce(func.sum(Transaction.qty * Transaction.unit_value), 0.0)).where(
            Transaction.vendor_id == vendor.id,
            Transaction.type == "sale",
            Transaction.occurred_at >= ninety_days_ago,
        )
    ) or 0.0

    comp_map = {c.key: c for c in score.components}
    consistency_info = comp_map.get("consistency")
    turnover_info = comp_map.get("turnover")
    waste_info = comp_map.get("waste")

    band_text = score.band.replace("_", " ").title()
    status_summary = (
        f"Provisional evaluation based on {score.days_of_history} days of verified transactions."
        if score.provisional
        else f"Full credit standing rating: {score.score:.1f}/100 ({band_text})."
    )

    statement = (
        f"VENDOR360 OPERATIONAL CREDIT ASSESSMENT REPORT\n"
        f"Store: {vendor.store_name} | Location: {vendor.locality or 'Pune'}\n"
        f"Score: {score.score:.1f}/100 | Rating: {band_text}\n"
        f"Summary: {status_summary}\n"
        f"- Trading Regularity: {consistency_info.detail if consistency_info else 'N/A'}\n"
        f"- Inventory Velocity: {turnover_info.detail if turnover_info else 'N/A'}\n"
        f"- Perishable Care: {waste_info.detail if waste_info else 'N/A'}\n"
        f"Verified 90-day gross trading volume: INR {sales_total:,.2f}.\n"
        f"Report verified by Vendor360 Micro-Lending Intelligence Core."
    )

    return CreditReportOut(
        store_name=vendor.store_name,
        owner_name=vendor.name,
        locality=vendor.locality or "—",
        phone=vendor.phone,
        generated_at=utcnow().strftime("%Y-%m-%d %H:%M UTC"),
        score=score.score,
        band=score.band,
        provisional=score.provisional,
        days_of_history=score.days_of_history,
        consistency_detail=consistency_info.detail if consistency_info else "N/A",
        turnover_detail=turnover_info.detail if turnover_info else "N/A",
        waste_detail=waste_info.detail if waste_info else "N/A",
        explanation=score.explanation,
        total_sales_volume_estimated=round(sales_total, 2),
        statement=statement,
    )


@router.get("/health-score/consents")
def list_consents(
    vendor: Vendor = Depends(current_vendor), db: Session = Depends(get_db)
):
    lenders = db.scalars(select(Lender)).all()
    consents = {
        c.lender_id: c
        for c in db.scalars(
            select(ScoreConsent).where(ScoreConsent.vendor_id == vendor.id)
        ).all()
    }
    return [
        {
            "lender_id": str(l.id),
            "name": l.name,
            "kind": l.kind,
            "granted": bool(consents.get(l.id) and consents[l.id].granted),
            "granted_at": consents[l.id].granted_at if l.id in consents else None,
        }
        for l in lenders
    ]


@router.post("/health-score/consents/{lender_id}")
def set_consent(
    lender_id: uuid.UUID,
    granted: bool,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    """Grant or revoke one lender's access to this vendor's score (TC-H03)."""
    if db.get(Lender, lender_id) is None:
        raise HTTPException(status_code=404, detail="Lender not found")

    consent = db.scalar(
        select(ScoreConsent).where(
            ScoreConsent.vendor_id == vendor.id, ScoreConsent.lender_id == lender_id
        )
    )
    if consent is None:
        consent = ScoreConsent(vendor_id=vendor.id, lender_id=lender_id)
        db.add(consent)

    consent.granted = granted
    if granted:
        consent.granted_at = utcnow()
        consent.revoked_at = None
    else:
        consent.revoked_at = utcnow()

    db.commit()
    return {"lender_id": str(lender_id), "granted": granted}


# --------------------------------------------------------------------- sync
@router.post("/sync/batch", response_model=SyncBatchOut)
def sync_batch(
    body: SyncBatchIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    outcome = apply_batch(
        db,
        vendor_id=vendor.id,
        device_id=body.device_id,
        events=[e.model_dump(mode="json") for e in body.events],
    )

    items = db.scalars(
        select(InventoryItem)
        .where(InventoryItem.vendor_id == vendor.id)
        .order_by(InventoryItem.sku_name)
    ).all()

    return SyncBatchOut(
        applied=outcome.applied,
        duplicates=outcome.duplicates,
        conflicts=outcome.conflicts,
        rejected=outcome.rejected,
        results=[SyncEventResult(**r.__dict__) for r in outcome.results],
        items=[ItemOut.model_validate(i) for i in items],
        server_time=utcnow(),
    )


@router.get("/sync/conflicts")
def list_conflicts(
    vendor: Vendor = Depends(current_vendor), db: Session = Depends(get_db)
):
    """Unreviewed conflicts, surfaced in-app rather than silently overwritten."""
    from ...models import ConflictAudit

    rows = db.scalars(
        select(ConflictAudit)
        .where(ConflictAudit.vendor_id == vendor.id, ConflictAudit.reviewed.is_(False))
        .order_by(ConflictAudit.created_at.desc())
    ).all()
    return [
        {
            "id": str(c.id),
            "item_id": str(c.item_id) if c.item_id else None,
            "field": c.field,
            "losing_value": c.losing_value,
            "winning_value": c.winning_value,
            "losing_device": c.losing_device,
            "created_at": c.created_at,
        }
        for c in rows
    ]


# -------------------------------------------------------------------- pools
@router.get("/vendor-network/pool-offers", response_model=list[PoolOut])
def pool_offers(
    vendor: Vendor = Depends(current_vendor), db: Session = Depends(get_db)
):
    candidates = pooling.find_pool_candidates(db, locality=vendor.locality)
    pooling.materialise_pools(db, candidates)

    pools = db.scalars(
        select(BargainPool).where(
            BargainPool.locality == (vendor.locality or "Unknown"),
            BargainPool.status == "open",
        )
    ).all()

    joined = {
        m.pool_id
        for m in db.scalars(
            select(PoolMember).where(
                PoolMember.vendor_id == vendor.id, PoolMember.opted_out.is_(False)
            )
        ).all()
    }

    out = []
    for p in pools:
        row = PoolOut.model_validate(p)
        row.progress = round(p.progress, 3)
        row.savings_per_unit = round(p.savings_per_unit, 2)
        row.member_count = len([m for m in p.members if not m.opted_out])
        row.joined = p.id in joined
        out.append(row)
    return out


@router.post("/vendor-network/pool-offers/{pool_id}/join", response_model=PoolOut)
def join_pool_route(
    pool_id: uuid.UUID,
    body: PoolJoinIn,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    if db.get(BargainPool, pool_id) is None:
        raise HTTPException(status_code=404, detail="Pool not found")
    pool = pooling.join_pool(db, pool_id=pool_id, vendor_id=vendor.id, qty=body.qty)
    row = PoolOut.model_validate(pool)
    row.progress = round(pool.progress, 3)
    row.savings_per_unit = round(pool.savings_per_unit, 2)
    row.member_count = len([m for m in pool.members if not m.opted_out])
    row.joined = True
    return row


@router.post("/vendor-network/pool-offers/{pool_id}/leave", response_model=PoolOut)
def leave_pool_route(
    pool_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    if db.get(BargainPool, pool_id) is None:
        raise HTTPException(status_code=404, detail="Pool not found")
    pool = pooling.leave_pool(db, pool_id=pool_id, vendor_id=vendor.id)
    row = PoolOut.model_validate(pool)
    row.progress = round(pool.progress, 3)
    row.savings_per_unit = round(pool.savings_per_unit, 2)
    row.member_count = len([m for m in pool.members if not m.opted_out])
    row.joined = False
    return row


# ------------------------------------------------------------------ heatmap
@router.get("/heatmap", response_model=HeatmapOut)
def heatmap(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    category: str | None = None,
    sku_name: str | None = None,
    days: int = Query(30, ge=1, le=180),
):
    result = build_heatmap(
        db, category=category, sku_name=sku_name, days=days, city=vendor.city
    )
    return HeatmapOut(
        cells=[HeatCellOut(**c.__dict__) for c in result.cells],
        suppressed_cells=result.suppressed_cells,
        category=result.category,
        days=result.days,
        max_demand=result.max_demand,
        total_demand=result.total_demand,
        suppliers=result.suppliers,
    )


# ------------------------------------------------------------------- expiry
# Markdown depth by urgency. Steeper as the window closes: a small discount on
# the last day clears nothing, and unsold stock is a total loss rather than a
# discounted sale.
_DISCOUNT_LADDER = [(0, 50), (1, 40), (2, 30), (3, 20), (5, 10)]


def _suggested_discount(days_left: int) -> int:
    for threshold, pct in _DISCOUNT_LADDER:
        if days_left <= threshold:
            return pct
    return 0


@router.get("/expiry", response_model=list[ExpiryItemOut])
def expiry_board(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    within_days: int = Query(7, ge=1, le=60),
):
    """Stock approaching expiry, ranked by value at risk."""
    horizon = date.today() + timedelta(days=within_days)
    items = db.scalars(
        select(InventoryItem).where(
            InventoryItem.vendor_id == vendor.id,
            InventoryItem.expires_on.is_not(None),
            InventoryItem.current_qty > 0,
        )
    ).all()

    out = []
    for item in items:
        expires = item.expires_on.date()
        if expires > horizon:
            continue
        days_left = (expires - date.today()).days
        value = item.current_qty * (item.unit_cost or 0)
        out.append(
            ExpiryItemOut(
                item_id=item.id,
                sku_name=item.sku_name,
                category=item.category,
                qty=item.current_qty,
                unit=item.unit,
                expires_on=expires,
                days_left=days_left,
                value_at_risk=round(value, 2),
                suggested_discount_pct=_suggested_discount(days_left),
                urgency="expired" if days_left < 0 else "critical" if days_left <= 1
                else "warning" if days_left <= 3 else "watch",
            )
        )

    out.sort(key=lambda e: (e.days_left, -e.value_at_risk))
    return out


# ---------------------------------------------------------------- dashboard
@router.get("/dashboard", response_model=DashboardOut)
def dashboard(
    vendor: Vendor = Depends(current_vendor), db: Session = Depends(get_db)
):
    """The two-second read the home screen is built around (UI/UX 5.1)."""
    today_start = utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today_start - timedelta(days=7)

    def sales_value(since):
        return float(
            db.scalar(
                select(
                    func.coalesce(func.sum(Transaction.qty * Transaction.unit_value), 0.0)
                ).where(
                    Transaction.vendor_id == vendor.id,
                    Transaction.type == "sale",
                    Transaction.occurred_at >= since,
                )
            )
            or 0.0
        )

    today_count = db.scalar(
        select(func.count()).select_from(Transaction).where(
            Transaction.vendor_id == vendor.id,
            Transaction.type == "sale",
            Transaction.occurred_at >= today_start,
        )
    )

    items = db.scalars(
        select(InventoryItem).where(InventoryItem.vendor_id == vendor.id)
    ).all()
    low = [i for i in items if i.current_qty <= i.reorder_point]

    soon = date.today() + timedelta(days=3)
    expiring = [
        i
        for i in items
        if i.expires_on and i.expires_on.date() <= soon and i.current_qty > 0
    ]
    at_risk = sum(i.current_qty * (i.unit_cost or 0) for i in expiring)

    score = compute_health_score(**_score_inputs(db, vendor.id))

    # The single most useful forward-looking signal, chosen between the nearest
    # festival and today's weather.
    signal = detail = None
    festivals = upcoming_festivals(date.today(), within_days=14)
    if festivals:
        fest = festivals[0]
        days_out = (fest.on - date.today()).days
        top = max(fest.lifts.items(), key=lambda kv: kv[1])
        signal = f"{fest.name} in {days_out} days"
        detail = (
            f"Expect ~{top[1]:.0%} more demand for "
            f"{CATEGORIES[top[0]].label_en.lower()}"
        )
    else:
        wx = forecast_weather(date.today() + timedelta(days=1), vendor.lat or 18.52, vendor.lon or 73.86)
        if wx.is_wet:
            signal = "Rain forecast tomorrow"
            detail = f"{wx.rain_mm}mm expected — monsoon goods move, cold drinks slow"

    # Pools are materialised lazily by the offers endpoint. Counting the table
    # directly here would report zero until the vendor happened to open that
    # screen, so the dashboard would under-report the thing it is meant to
    # advertise. Materialising is idempotent -- existing pools are skipped.
    pooling.materialise_pools(
        db, pooling.find_pool_candidates(db, locality=vendor.locality)
    )
    open_pools = db.scalar(
        select(func.count()).select_from(BargainPool).where(
            BargainPool.locality == (vendor.locality or "Unknown"),
            BargainPool.status == "open",
        )
    )

    return DashboardOut(
        vendor=VendorOut.model_validate(vendor),
        today_sales_value=round(sales_value(today_start), 2),
        today_transaction_count=int(today_count or 0),
        week_sales_value=round(sales_value(week_start), 2),
        low_stock_count=len(low),
        expiring_soon_count=len(expiring),
        value_at_risk=round(at_risk, 2),
        health_score=score.score,
        health_band=score.band,
        top_signal=signal,
        top_signal_detail=detail,
        pending_pools=int(open_pools or 0),
    )


@router.get("/signals")
def signals_console(
    vendor: Vendor = Depends(current_vendor),
    days: int = Query(14, ge=1, le=60),
):
    """Weather and festival feed driving the forecasts (TC-F01/F02)."""
    today = date.today()
    lat, lon = vendor.lat or 18.52, vendor.lon or 73.86

    weather = []
    for i in range(days):
        d = today + timedelta(days=i)
        w = forecast_weather(d, lat, lon)
        weather.append(
            {
                "on": d.isoformat(),
                "temp_c": w.temp_c,
                "rain_mm": w.rain_mm,
                "rain_prob": w.rain_prob,
                "is_wet": w.is_wet,
            }
        )

    festivals = [
        {
            "name": f.name,
            "name_hi": f.name_hi,
            "on": f.on.isoformat(),
            "days_away": (f.on - today).days,
            "lead_days": f.lead_days,
            "lifts": {
                CATEGORIES[k].label_en: round(v * 100) for k, v in f.lifts.items() if k in CATEGORIES
            },
        }
        for f in upcoming_festivals(today, within_days=90)
    ]

    return {"weather": weather, "festivals": festivals}
