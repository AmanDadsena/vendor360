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

    # Only consulted when the number is new. An existing account's role is a
    # property of the account, not of what the sign-in form happened to say.
    role: str = "vendor"

    # Distributor signup only.
    business_name: str | None = None
    locality: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

    # Which shell the client should build. Explicit rather than inferred from
    # which of the two payloads below is populated, so the client never has to
    # guess from a null.
    role: str = "vendor"

    vendor: "VendorOut | None" = None
    distributor: "DistributorOut | None" = None


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


# ----------------------------------------------------------- distributors
class DistributorOut(BaseModel):
    """The signed-in distributor, flattened across user and organisation.

    The client only ever needs "who am I and which business do I act for", so
    it gets one object rather than having to join two.
    """

    id: uuid.UUID
    supplier_id: uuid.UUID
    name: str
    phone: str
    language_pref: str
    business_name: str
    kind: str
    locality: str
    city: str
    lead_days: int
    min_order_value: float
    rating: float


class SupplierCardOut(BaseModel):
    """A distributor as a vendor sees them while choosing who to connect to."""

    id: uuid.UUID
    name: str
    kind: str
    locality: str
    city: str
    categories: list[str]
    lead_days: int
    min_order_value: float
    rating: float
    phone: str | None = None
    distance_km: float | None = None
    catalog_size: int = 0
    connected: bool = False
    fill_rate: float | None = None


class ConnectIn(BaseModel):
    shares_demand: bool = True
    credit_terms_days: int = 0


class ConnectionOut(BaseModel):
    supplier_id: uuid.UUID
    supplier_name: str
    locality: str
    status: str
    shares_demand: bool
    scope_categories: list[str]
    credit_terms_days: int
    credit_limit: float
    connected_at: datetime
    outstanding: float = 0
    open_orders: int = 0
    fill_rate: float | None = None


class CatalogEntryOut(ORMModel):
    id: uuid.UUID
    supplier_id: uuid.UUID
    sku_name: str
    category: str
    unit: str
    pack_size: float
    pack_price: float
    unit_price: float
    moq_packs: int
    lead_days: int | None = None
    available_packs: float | None = None
    active: bool


class CatalogEntryIn(BaseModel):
    sku_name: str = Field(min_length=1, max_length=160)
    category: str = "staples"
    unit: str = "pc"
    pack_size: float = Field(gt=0)
    pack_price: float = Field(ge=0)
    moq_packs: int = Field(default=1, ge=1)
    lead_days: int | None = None
    available_packs: float | None = None


class CatalogEntryUpdate(BaseModel):
    pack_price: float | None = None
    pack_size: float | None = None
    moq_packs: int | None = None
    lead_days: int | None = None
    available_packs: float | None = None
    active: bool | None = None


class PriceListRowOut(BaseModel):
    """One parsed CSV row, with whatever is wrong with it attached.

    Import is preview-then-commit: a distributor sees every row and its
    problems before anything is written, because a silently half-applied price
    list is worse than a rejected one.
    """

    row: int
    sku_name: str
    category: str
    unit: str
    pack_size: float
    pack_price: float
    moq_packs: int
    action: str  # create | update | skip
    errors: list[str]


class PriceListPreviewOut(BaseModel):
    rows: list[PriceListRowOut]
    valid: int
    invalid: int
    will_create: int
    will_update: int


class PriceListImportIn(BaseModel):
    csv_text: str
    commit: bool = False


# ----------------------------------------------------------------- sourcing
class SourcingOptionOut(BaseModel):
    """One way to fill a shortfall, with the reasoning that ranked it.

    `reasons` exists so the UI never presents an unexplained ordering. A vendor
    who cannot see why the top option is on top has no way to disagree with it,
    and will stop trusting the ranking.
    """

    supplier_id: uuid.UUID
    supplier_name: str
    catalog_entry_id: uuid.UUID
    sku_name: str
    unit: str
    pack_size: float
    pack_price: float
    unit_price: float
    moq_packs: int

    packs_needed: float
    qty_supplied: float
    landed_cost: float
    lead_days: int
    arrives_in_time: bool
    fill_rate: float | None
    distance_km: float | None
    score: float
    reasons: list[str]


class SourcingOut(BaseModel):
    item_id: uuid.UUID
    sku_name: str
    unit: str
    current_qty: float
    reorder_point: float
    shortfall: float
    days_of_cover: float | None
    options: list[SourcingOptionOut]
    unconnected_count: int


# ------------------------------------------------------------------- orders
class OrderLineIn(BaseModel):
    catalog_entry_id: uuid.UUID | None = None
    item_id: uuid.UUID | None = None
    sku_name: str | None = None
    category: str | None = None
    unit: str | None = None
    pack_size: float | None = None
    unit_price: float | None = None
    packs: float = Field(gt=0)


class OrderCreateIn(BaseModel):
    supplier_id: uuid.UUID
    lines: list[OrderLineIn] = Field(min_length=1)
    note: str | None = None
    pool_id: uuid.UUID | None = None

    # Device-minted, so an order placed with no signal replays exactly once.
    client_event_id: uuid.UUID | None = None

    # Skip the draft state entirely. The app's one-tap reorder does this; the
    # cart flow does not.
    place_immediately: bool = False


class OrderLineOut(ORMModel):
    id: uuid.UUID
    catalog_entry_id: uuid.UUID | None
    item_id: uuid.UUID | None
    sku_name: str
    category: str
    unit: str
    pack_size: float
    unit_price: float
    packs_ordered: float
    packs_confirmed: float | None
    packs_delivered: float | None
    qty_ordered: float
    line_total: float


class OrderEventOut(ORMModel):
    actor_role: str
    from_status: str | None
    to_status: str
    note: str | None
    created_at: datetime


class OrderOut(BaseModel):
    id: uuid.UUID
    code: str
    status: str
    vendor_id: uuid.UUID
    vendor_name: str
    supplier_id: uuid.UUID
    supplier_name: str
    supplier_phone: str | None = None

    placed_at: datetime | None = None
    expected_at: datetime | None = None
    delivered_at: datetime | None = None

    payment_terms_days: int
    amount_total: float
    amount_paid: float
    amount_due: float
    line_count: int
    note: str | None = None
    pool_id: uuid.UUID | None = None
    lines: list[OrderLineOut] = []
    events: list[OrderEventOut] = []


class LineQuantityIn(BaseModel):
    line_id: uuid.UUID
    packs: float = Field(ge=0)


class OrderFulfilIn(BaseModel):
    """Confirm or deliver, optionally amending per-line quantities.

    Omitting `lines` means "all of it, as ordered" — the common case, and one
    the distributor should not have to type out.
    """

    lines: list[LineQuantityIn] | None = None
    note: str | None = None


class OrderCancelIn(BaseModel):
    reason: str | None = None


# ------------------------------------------------------------------- ledger
class LedgerLineOut(BaseModel):
    id: uuid.UUID
    kind: str
    amount: float
    order_code: str | None
    counterparty: str
    due_on: datetime | None
    overdue: bool
    note: str | None
    created_at: datetime


class LedgerOut(BaseModel):
    outstanding: float
    overdue: float
    due_this_week: float
    entries: list[LedgerLineOut]


class PaymentIn(BaseModel):
    vendor_id: uuid.UUID
    amount: float = Field(gt=0)
    order_id: uuid.UUID | None = None
    note: str | None = None


# ------------------------------------------------ distributor intelligence
class DemandLineOut(BaseModel):
    """Aggregate expected demand for one SKU across consenting shops."""

    sku_name: str
    category: str
    unit: str
    expected_qty: float
    shop_count: int
    catalog_entry_id: uuid.UUID | None
    packs_to_stock: float | None
    est_revenue: float
    confidence: str


class AtRiskShopOut(BaseModel):
    """A shop that runs out before this distributor's lead time can reach it.

    The most actionable screen in the distributor product: not a report, a
    prompt to pick up the phone.
    """

    vendor_id: uuid.UUID
    store_name: str
    locality: str
    sku_name: str
    unit: str
    current_qty: float
    daily_rate: float
    days_of_cover: float
    lead_days: int
    shortfall_by_arrival: float
    suggested_packs: float
    est_value: float


class DistributorVendorOut(BaseModel):
    vendor_id: uuid.UUID
    store_name: str
    owner_name: str
    locality: str
    phone: str
    connected_at: datetime
    order_count: int
    delivered_count: int
    revenue: float
    outstanding: float
    fill_rate: float | None
    last_order_at: datetime | None
    shares_demand: bool


class DeadLineOut(BaseModel):
    catalog_entry_id: uuid.UUID
    sku_name: str
    category: str
    days_since_last_order: int | None
    pack_price: float


class DemandOut(BaseModel):
    horizon_days: int
    consenting_shops: int
    total_connected: int
    lines: list[DemandLineOut]
    at_risk: list[AtRiskShopOut]
    dead_lines: list[DeadLineOut]


class DistributorSummaryOut(BaseModel):
    business_name: str
    needs_action: int
    to_dispatch: int
    in_transit: int
    delivered_this_week: int
    revenue_this_week: float
    outstanding: float
    overdue: float
    connected_shops: int
    at_risk_count: int
    open_pool_count: int
    top_prompt: str | None
    top_prompt_detail: str | None


class PoolQuoteIn(BaseModel):
    bulk_unit_price: float = Field(gt=0)


# --------------------------------------------------------------- onboarding
class MasterSkuOut(BaseModel):
    key: str
    name_en: str
    name_hi: str
    name_mr: str
    category: str
    unit: str
    typical_pack: float
    typical_price: float
    popularity: int


class QuickAddIn(BaseModel):
    keys: list[str] = Field(min_length=1)


class QuickAddOut(BaseModel):
    created: int
    skipped: int
    items: list[ItemOut]


TokenResponse.model_rebuild()
