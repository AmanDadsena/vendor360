"""Pydantic request/response models.

Kept separate from the ORM so the wire format can stay stable while the schema
evolves, and so no handler can accidentally serialise a server-owned column
(computed reorder points, conflict audits) that a client has no business
seeing.
"""
from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --------------------------------------------------------------- auth
class OtpRequest(BaseModel):
    phone: str = Field(min_length=10, max_length=15)


class OtpRequestResponse(BaseModel):
    sent: bool
    expires_in: int
    # Present only while `EXPOSE_OTP` is set, so the prototype is demonstrable
    # without an SMS gateway. Never populated in a real deployment.
    dev_code: str | None = None


class OtpVerify(BaseModel):
    phone: str
    code: str = Field(min_length=4, max_length=8)
    name: str | None = None
    store_name: str | None = None
    language_pref: str = "hi"


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    vendor: "VendorOut"


class VendorOut(ORMModel):
    id: uuid.UUID
    name: str
    store_name: str
    phone: str
    language_pref: str
    locality: str | None = None
    city: str
    lat: float | None = None
    lon: float | None = None
    health_score: float | None = None
    supplier_lead_days: int


# ---------------------------------------------------------- inventory
class ItemOut(ORMModel):
    id: uuid.UUID
    sku_name: str
    category: str
    current_qty: float
    unit: str
    reorder_point: float
    unit_cost: float
    unit_price: float
    shelf_life_days: int | None = None
    expires_on: datetime | None = None
    sync_status: str
    last_updated: datetime | None = None


class ItemCreate(BaseModel):
    sku_name: str
    category: str = "staples"
    current_qty: float = 0
    unit: str = "pc"
    unit_cost: float = 0
    unit_price: float = 0
    # The device may supply its own UUID so an item created offline keeps one
    # identity across the sync boundary.
    id: uuid.UUID | None = None


class ItemUpdate(BaseModel):
    sku_name: str | None = None
    category: str | None = None
    current_qty: float | None = None
    unit: str | None = None
    unit_cost: float | None = None
    unit_price: float | None = None


class StockAdviceOut(BaseModel):
    reorder_point: float
    safety_stock: float
    mean_daily_demand: float
    days_of_cover: float | None
    capped_by_shelf_life: bool
    reason: str
    suggested_order_qty: float


class ItemDetailOut(ItemOut):
    advice: StockAdviceOut | None = None
    is_low: bool = False


# -------------------------------------------------------- transactions
class MovementIn(BaseModel):
    item_id: uuid.UUID
    qty: float = Field(gt=0)
    movement: str = Field(pattern="^(sale|restock|wastage)$")
    source: str = "manual"
    confidence: float = 1.0
    raw_text: str | None = None
    occurred_at: datetime | None = None


class TransactionOut(ORMModel):
    id: uuid.UUID
    item_id: uuid.UUID
    type: str
    qty: float
    unit_value: float
    source: str
    confidence: float
    occurred_at: datetime


# --------------------------------------------------------------- voice
class VoiceEntryIn(BaseModel):
    transcript: str
    language: str = "hi"
    asr_confidence: float = 1.0
    # False returns the parse for confirmation without touching inventory,
    # which is the design guide's mandatory confirm step (UI/UX 5.2).
    commit: bool = False


class ParsedLineOut(BaseModel):
    sku_name: str
    qty: float
    unit: str | None
    movement: str
    confidence: float
    needs_review: bool
    matched_text: str
    category: str | None = None
    item_id: uuid.UUID | None = None
    known_item: bool = False


class VoiceEntryOut(BaseModel):
    transcript: str
    language: str
    movement: str
    overall_confidence: float
    needs_review: bool
    lines: list[ParsedLineOut]
    unmatched_tokens: list[str]
    committed: bool = False


# ----------------------------------------------------------------- ocr
class OcrEntryIn(BaseModel):
    raw_text: str
    ocr_confidence: float = 1.0
    captured_on: date | None = None
    supplier_hint: str | None = None
    commit: bool = False


class ReceiptLineOut(BaseModel):
    raw: str
    sku_name: str | None
    qty: float | None
    unit: str | None
    rate: float | None
    amount: float | None
    category: str | None
    shelf_life_days: int | None
    expires_on: date | None
    confidence: float
    needs_review: bool
    issues: list[str]


class OcrEntryOut(BaseModel):
    supplier: str | None
    captured_on: date
    stated_total: float | None
    computed_total: float
    total_matches: bool
    overall_confidence: float
    review_count: int
    lines: list[ReceiptLineOut]
    committed: bool = False


# ------------------------------------------------------------ forecast
class ForecastDayOut(BaseModel):
    on: date
    predicted: float
    lower: float
    upper: float
    driver: str | None
    driver_effect: float
    baseline: float


class ForecastOut(BaseModel):
    item_id: uuid.UUID
    sku_name: str
    category: str
    model_version: str
    used_fallback: bool
    history_days: int
    total_predicted: float
    days: list[ForecastDayOut]
    headline: str


# --------------------------------------------------------------- sync
class SyncEventIn(BaseModel):
    client_event_id: uuid.UUID
    local_seq: int
    kind: str = "inventory_delta"
    client_ts: datetime | None = None
    payload: dict


class SyncBatchIn(BaseModel):
    device_id: str
    events: list[SyncEventIn]


class SyncEventResult(BaseModel):
    client_event_id: str
    status: str
    detail: str = ""
    item_id: str | None = None


class SyncBatchOut(BaseModel):
    applied: int
    duplicates: int
    conflicts: int
    rejected: int
    results: list[SyncEventResult]
    # The authoritative state the device reconciles against (TRD 7.1).
    items: list[ItemOut]
    server_time: datetime


# -------------------------------------------------------- health score
class ScoreComponentOut(BaseModel):
    key: str
    label: str
    value: float
    weight: float
    contribution: float
    detail: str


class HealthScoreOut(BaseModel):
    score: float
    band: str
    provisional: bool
    days_of_history: int
    explanation: str
    components: list[ScoreComponentOut]


# --------------------------------------------------------------- pools
class PoolOut(ORMModel):
    id: uuid.UUID
    sku_name: str
    category: str
    unit: str
    locality: str
    target_qty: float
    committed_qty: float
    base_unit_price: float
    bulk_unit_price: float
    status: str
    closes_at: datetime | None = None
    progress: float = 0
    savings_per_unit: float = 0
    member_count: int = 0
    joined: bool = False


class PoolJoinIn(BaseModel):
    qty: float = Field(gt=0)


# ------------------------------------------------------------- heatmap
class HeatCellOut(BaseModel):
    lat: float
    lon: float
    intensity: float
    demand_qty: float
    demand_value: float
    vendor_count: int
    top_sku: str | None
    shortage_count: int


class HeatmapOut(BaseModel):
    cells: list[HeatCellOut]
    suppressed_cells: int
    category: str | None
    days: int
    max_demand: float
    total_demand: float
    suppliers: list[dict]


# ------------------------------------------------------------ dashboard
class ExpiryItemOut(BaseModel):
    item_id: uuid.UUID
    sku_name: str
    category: str
    qty: float
    unit: str
    expires_on: date
    days_left: int
    value_at_risk: float
    suggested_discount_pct: int
    urgency: str


class DashboardOut(BaseModel):
    vendor: VendorOut
    today_sales_value: float
    today_transaction_count: int
    week_sales_value: float
    low_stock_count: int
    expiring_soon_count: int
    value_at_risk: float
    health_score: float | None
    health_band: str | None
    top_signal: str | None
    top_signal_detail: str | None
    pending_pools: int


TokenResponse.model_rebuild()
