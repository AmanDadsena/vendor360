# Vendor360 — The Order Loop, Distributor Intelligence, and Painless Setup

**Date:** 2026-08-31
**Status:** approved, ready for implementation
**Slices:** A (order loop) · B (distributor intelligence) · D (setup)

---

## The problem

Vendor360 predicts and then stops. `forecasting.py` says a shop will sell 14 kg
of atta; `safety_stock.py` sets the reorder point at 9 kg; the dashboard shows a
red chip. Then the vendor picks up a phone.

`Supplier` is a map pin — name, lat/lon, `lead_days`, `min_order_value`, `phone`.
It has no login, no catalogue, no prices, and no way to receive anything.
`BargainPool.supplier_id` is nullable and nothing ever fills it: the pooling
engine computes a bulk discount across three or more vendors and then has no
counterparty to accept it.

So the distributor is not an underserved user of Vendor360. The distributor is
the missing half of the product, and their absence is what caps the vendor half.

## What this builds

1. **The order loop.** Distributors become real accounts with catalogues.
   A prediction becomes a draft order becomes a placed order becomes a delivery
   that restocks inventory and feeds the next forecast.
2. **Distributor intelligence.** The forecasting engine pointed at a vendor book
   instead of one shop: what my shops will need, who runs out before I can
   reach them, which lines are dead.
3. **Painless setup.** Nobody types two hundred SKUs. Tap from a master
   catalogue, snap a bill, or upload a price list.

Deferred to later cycles: full khata with a payment gateway (slice C — a thin
ledger is included here), and the global polish pass (slice E).

---

## Decisions taken

| Decision | Choice | Why |
|---|---|---|
| Shipping model | One Flutter binary, role-switched shells | `vendor360_core` has zero dependencies and `vendor360_ui` imports no app models, so the design system is reusable for free. One build, one test story, one run command. Flutter web gives a distributor a desk console from the same code. |
| Distributor identity | New `DistributorUser` → `Supplier` | `Supplier` is already the org (locality, lead days, MOQ, rating). An org has staff. `Supplier.phone` currently means "call this number", not "authenticate as this". |
| Data visibility | Connection-scoped consent, frozen at grant time | One revocable tap, scoped to the categories that distributor actually supplies. Preserves the heatmap's k-anonymity stance for non-customers. |
| Order modelling | First-class `PurchaseOrder` tables | Orders must be queryable and stateful and need a distributor-side inbox. Rejected: orders as `SyncEvent` payloads (an append-only idempotency log is bad at "show unconfirmed orders"), and orders as size-one `BargainPool`s (pools are locality-scoped, shortage-grouped, 48h-windowed; orders are none of those). |
| External dependencies | Stubbed, with the real pipeline behind them | The project's established convention (Bhashini, camera OCR). No payment gateway; recording a payment is a manual act by either side. |

---

## 1. Identity and roles

The JWT gains a `role` claim, `"vendor"` or `"distributor"`.

`current_vendor` keeps its exact signature and body and adds one assertion:
the token's role must be `vendor`. **Every existing route is untouched**, and a
distributor token cannot reach vendor data. `current_distributor` is its mirror,
resolving a `DistributorUser` and returning it with its `Supplier` loaded.

`POST /auth/otp/request` is unchanged — it is phone-keyed and role-agnostic.

`POST /auth/otp/verify` resolves the verified phone against `Vendor`, then
`DistributorUser`, and returns the resolved role alongside the token so the
client knows which shell to build. An unknown phone still auto-creates a
`Vendor` — that is a deliberate existing decision ("for this audience an extra
form is an extra reason to give up") and it is preserved. Signing up as a
distributor means passing `role: "distributor"` in the verify body, which the
onboarding role fork sets.

Phone numbers are unique **across** both principal tables. A phone already
registered in the other role returns 409 rather than silently creating a second
identity.

### Threat notes

- A distributor token replayed against `/inventory` fails at `current_vendor`'s
  role assertion, before any query runs.
- Consent scope is frozen (see §2) so catalogue growth cannot widen access.
- Every distributor-side query is scoped by `supplier_id` taken from the token's
  resolved user, never from the request body — the same discipline
  `current_vendor` already enforces.

---

## 2. Data model

All new tables follow the existing conventions: `GUID` primary keys defaulting
to `uuid4`, `TZDateTime` timestamps, `JSONColumn` for structured blobs,
Postgres-compatible column types.

### `DistributorUser`

Login for a `Supplier` org.

| Column | Type | Notes |
|---|---|---|
| `id` | GUID pk | |
| `supplier_id` | GUID fk → suppliers | cascade delete |
| `name` | String(120) | |
| `phone` | String(20) unique, indexed | unique across `Vendor` too, enforced in the verify handler |
| `created_at` | TZDateTime | |

### `CatalogEntry`

What a distributor sells, at what price.

| Column | Type | Notes |
|---|---|---|
| `id` | GUID pk | |
| `supplier_id` | GUID fk, indexed | |
| `sku_name` | String(160) | |
| `category` | String(60) | from the existing `catalog.CATEGORIES` taxonomy |
| `unit` | String(16) | kg, l, pc |
| `pack_size` | Float | units per case |
| `pack_price` | Float | price of one case |
| `moq_packs` | Integer | minimum order, in cases |
| `lead_days` | Integer nullable | overrides the supplier default |
| `available_packs` | Float nullable | null = unlimited |
| `active` | Boolean | soft delete, so historic order lines keep resolving |
| `updated_at` | TZDateTime | |

Index on `(supplier_id, sku_name)`.

**`pack_size` is the load-bearing field.** Real distributors sell cases, not
units. A vendor needing 12 kg of atta buys two 10 kg cases and receives 20 kg.
This is why MOQ exists, why pooling is worth coordinating, and why the existing
`pooling.discount_for` reasoning in multiples of a typical single order is
coherent at all.

### `VendorDistributor`

The trading connection and the consent it carries. Modelled on `ScoreConsent`:
an auditable, revocable row, not a boolean.

| Column | Type | Notes |
|---|---|---|
| `id` | GUID pk | |
| `vendor_id` | GUID fk, indexed | |
| `supplier_id` | GUID fk, indexed | |
| `status` | String(16) | `active` \| `paused` \| `ended` |
| `shares_demand` | Boolean | the consent flag |
| `scope_categories` | JSONColumn | **frozen at grant time** |
| `credit_terms_days` | Integer | 0 = cash on delivery |
| `credit_limit` | Float | 0 = no limit set |
| `connected_at` | TZDateTime | |
| `revoked_at` | TZDateTime nullable | |

`UniqueConstraint(vendor_id, supplier_id)`.

**Frozen scope is a security property, not ceremony.** If `scope_categories`
were computed live from the distributor's catalogue, a grain wholesaler could
add `dairy` to their price list tomorrow and silently gain visibility into a
shop's milk forecasts. Freezing the snapshot at grant time means widening access
requires the vendor to re-consent. `test_connections.py` asserts this directly.

### `PurchaseOrder`

| Column | Type | Notes |
|---|---|---|
| `id` | GUID pk | |
| `code` | String(16) unique | human-readable, e.g. `PO-4821` — the two parties talk on the phone and need something to say |
| `vendor_id`, `supplier_id` | GUID fk, indexed | |
| `status` | String(16) | see the state machine below |
| `placed_at` / `confirmed_at` / `dispatched_at` / `delivered_at` / `cancelled_at` | TZDateTime nullable | |
| `expected_at` | TZDateTime nullable | placed_at + lead days |
| `payment_terms_days` | Integer | snapshotted from the connection |
| `amount_total` / `amount_paid` | Float | |
| `pool_id` | GUID nullable | the counterparty `BargainPool` never had |
| `client_event_id` | GUID unique nullable | offline idempotency |
| `note` | String(300) nullable | |
| `created_at` | TZDateTime | |

### `PurchaseOrderLine`

| Column | Type | Notes |
|---|---|---|
| `id` | GUID pk | |
| `order_id` | GUID fk, indexed | cascade |
| `catalog_entry_id` | GUID nullable | free-text lines permitted |
| `item_id` | GUID nullable | the vendor's `InventoryItem`, so delivery restocks the right row |
| `sku_name`, `unit` | String | snapshotted, so a renamed catalogue entry doesn't rewrite history |
| `pack_size`, `unit_price` | Float | snapshotted for the same reason |
| `packs_ordered` | Float | what the vendor asked for |
| `packs_confirmed` | Float nullable | what the distributor committed to |
| `packs_delivered` | Float nullable | what actually arrived |
| `line_total` | Float | |

**Three quantities, not one.** `ordered ≠ confirmed ≠ delivered` is the reality
of Indian wholesale; part-fills are the norm. Collapsing them destroys **fill
rate**, the single most useful signal for ranking who to buy from. The existing
`Transaction` model made the same call by refusing to treat wastage as a
negative sale.

### `OrderEvent`

Append-only status journal: `order_id`, `actor_role`, `actor_id`, `from_status`,
`to_status`, `note`, `created_at`. Exists for disputes ("you said you dispatched
it Tuesday") and gives the vendor-facing order timeline for free.

### `LedgerEntry`

Thin slice of khata. `vendor_id`, `supplier_id`, `order_id` nullable, `kind`
(`charge` | `payment` | `adjustment`), `amount`, `due_on`, `note`, `created_at`.

Outstanding balance is `sum(charges) − sum(payments)`. There is no payment
gateway; recording a payment is a manual act by either side, consistent with how
the project stubs every external dependency.

### Order state machine

```
draft ──place──> placed ──confirm──> confirmed ──dispatch──> dispatched ──deliver──> delivered
  │                 │                    │                        │
  └───cancel────────┴────cancel/reject───┴──────cancel────────────┘
                                                                   (terminal: delivered, cancelled)
```

Transitions are validated in `ordering.py`, not at the call site, so
`delivered → placed` is impossible from any route. `confirm` may amend
`packs_confirmed` per line; `deliver` may amend `packs_delivered`.

---

## 3. Services

### `services/ordering.py`

- `packs_needed(shortfall, pack_size, moq_packs)` — `ceil(shortfall / pack_size)`,
  raised to MOQ. Returns both the pack count and the resulting unit quantity, so
  the UI can show the rounding rather than hide it.
- `draft_from_advice(vendor, items, supplier)` — turns low-stock advice into a
  priced draft.
- `transition(order, to_status, actor)` — the state machine; writes an
  `OrderEvent`; rejects illegal moves with a domain error.
- `apply_delivery(order)` — writes a `restock` `Transaction` per line and bumps
  `InventoryItem.current_qty`. **This is the line that closes the loop**: a
  delivery feeds the forecast that predicted it. Idempotent on
  `order.delivered_at`.
- `fill_rate(supplier_id, vendor_id=None)` — delivered ÷ ordered over the last
  N orders.

### `services/sourcing.py`

Given a vendor and a shortfall, rank connected distributors on:

- **landed cost** — MOQ-aware: the true cost is `packs × pack_price`, not a
  headline unit rate, because reaching MOQ can make the cheaper unit price the
  more expensive order.
- **lead days vs days of cover** — a distributor who cannot arrive before the
  shop runs out is ranked below one who can, whatever the price.
- **historical fill rate** — a 96% supplier beats a 70% supplier at equal cost.
- **distance** — from the existing lat/lon.

Returns a ranked list with the reasons attached, so the UI can say
*"₹18 cheaper per kg · arrives 1 day sooner · fills 96% of orders"* rather than
presenting an unexplained ordering.

### `services/distributor_intel.py`

Slice B, and every query is filtered by consent before it aggregates.

- `demand_outlook(supplier, days)` — per SKU in the distributor's catalogue,
  aggregate the forecasts of connected, consenting vendors whose
  `scope_categories` include that SKU's category.
- `at_risk_vendors(supplier)` — shops whose days of cover is less than this
  distributor's lead time: *they will run out before you can reach them*. The
  highest-value screen in the distributor product, because it is a prompt to
  sell.
- `book_summary(supplier)` — revenue, order count, fill rate and outstanding
  balance per connected vendor.
- `dead_lines(supplier, days)` — catalogue entries with no orders in N days.

### `services/onboarding.py`

Slice D.

- A master kirana catalogue of ~120 common SKUs across the existing category
  taxonomy, with typical units and shelf lives, so a new shop taps instead of
  types.
- `quick_add(vendor, sku_keys)` — bulk-create inventory items from picks.
- `parse_price_list(csv_bytes)` — distributor CSV ingest, returning a preview
  with per-row validation before anything is committed.
- Bill import reuses the existing `ocr_parser` unchanged.

---

## 4. API surface

### Vendor side

| Method | Path | Purpose |
|---|---|---|
| GET | `/distributors` | discover: near me, by category |
| POST | `/distributors/{id}/connect` | grant consent, freeze scope |
| DELETE | `/distributors/{id}/connect` | revoke |
| GET | `/connections` | my distributors, with terms and outstanding |
| GET | `/sourcing/{item_id}` | ranked options for one shortfall |
| POST | `/orders` | create a draft |
| GET | `/orders` | my orders, filterable by status |
| GET | `/orders/{id}` | detail with timeline |
| POST | `/orders/{id}/place` | draft → placed |
| POST | `/orders/{id}/cancel` | |
| POST | `/orders/{id}/receive` | confirm delivery → restock |
| GET | `/ledger` | outstanding by distributor |
| GET | `/onboarding/master-catalog` | the ~120 SKU starter set |
| POST | `/onboarding/quick-add` | bulk-create from picks |

### Distributor side — all under `/dist`, all behind `current_distributor`

| Method | Path | Purpose |
|---|---|---|
| GET | `/dist/summary` | the Today screen |
| GET | `/dist/orders` | inbox, filterable |
| POST | `/dist/orders/{id}/confirm` | with per-line confirmed packs |
| POST | `/dist/orders/{id}/dispatch` | |
| POST | `/dist/orders/{id}/deliver` | with per-line delivered packs |
| POST | `/dist/orders/{id}/reject` | |
| GET/POST | `/dist/catalog` | list, create |
| PATCH/DELETE | `/dist/catalog/{id}` | update, soft-delete |
| POST | `/dist/catalog/import` | CSV, preview-then-commit |
| GET | `/dist/vendors` | the book: fill rate, revenue, outstanding |
| GET | `/dist/demand` | slice B outlook + at-risk shops |
| GET | `/dist/pools` | open pools matching my catalogue |
| POST | `/dist/pools/{id}/quote` | the counterparty pools never had |
| GET | `/dist/ledger` | receivables |
| POST | `/dist/payments` | record a payment received |

---

## 5. Client

`sessionProvider` holds a `Principal` — vendor or distributor — and the router's
redirect goes from two-state to three-state. Two shells, one binary.

**Vendor shell** keeps its five tabs unchanged and gains:

- an **Order** action on every low-stock inventory row and forecast row, opening
  the sourcing sheet → cart → place
- an **Orders** screen with the per-order timeline and the receive-delivery flow
- a **Distributors** screen: discover, connect, terms, outstanding

**Distributor shell**, five tabs of its own:

1. **Today** — orders needing action, today's dispatch list, money due
2. **Orders** — the inbox: confirm, part-fill, dispatch, deliver
3. **Demand** — slice B: what my shops will need, who is about to run out
4. **Catalog** — prices, pack sizes, MOQ, CSV import
5. **Shops** — the book, fill rate, ledger

**Onboarding** forks on *"I run a shop"* / *"I supply shops"*, then runs a guided
setup: language → categories → tap your top SKUs from the master catalogue (or
snap a bill) → connect to two nearby distributors. Target: **under two minutes
to a usable catalogue.**

### Smoothness, concretely

- Order placement rides the **existing offline queue** with a `client_event_id`,
  so an order placed with no signal lands on reconnect, exactly once.
- Pack rounding is shown, never hidden: *"need 12 kg → 2 cases of 10 kg = 20 kg,
  ₹840"*.
- The sourcing sheet always shows its reasoning.
- CSV import previews and flags rows before committing.
- Every new screen gets the loading, empty and error states the existing screens
  have, using `V360Skeleton` and `V360Banner`.

---

## 6. Testing

Backend cases keep the existing `TC-` naming convention.

| File | Covers |
|---|---|
| `test_ordering.py` | pack rounding and MOQ; illegal state transitions rejected; part-fill arithmetic; delivery restocks the right item and is idempotent |
| `test_sourcing.py` | MOQ-aware landed cost beats headline unit price; lead time vs cover; fill-rate weighting |
| `test_distributor_intel.py` | a non-consenting vendor never appears in any aggregate; **catalogue growth does not widen frozen scope**; at-risk detection |
| `test_connections.py` | grant and revoke; cross-role token rejection; duplicate phone across roles returns 409 |
| `test_onboarding.py` | CSV preview validation; quick-add creates items with correct shelf lives |

Client: widget tests for each new screen's three states, and `vendor360_core`
tests for the new `PackQuantity` value object.

`seed.py` is extended with distributors, catalogues, connections and order
history, so every new screen has believable data on first run — the existing
seed already builds 40 stores over 90 days and this continues that.

---

## Out of scope

- Payment gateway / UPI settlement (slice C beyond the ledger)
- Real SMS delivery for OTP (unchanged: the code is returned in the response)
- The global polish pass across the original eleven screens (slice E)
- Multi-user distributor orgs beyond the schema supporting them
