# Two-Sided Marketplace Implementation Plan

**Goal:** Turn Vendor360 from a vendor-only prediction app into a two-sided
platform where predictions become orders, distributors are real accounts with
catalogues and demand intelligence, and setup takes under two minutes.

**Architecture:** One Flutter binary with role-switched shells over a FastAPI
backend that gains a second principal type. Orders are first-class stateful
entities with a validated status machine; distributor visibility is gated by a
consent scope frozen at grant time.

**Tech Stack:** FastAPI · SQLAlchemy 2.0 (Postgres-compatible on SQLite) ·
scikit-learn · Flutter · Riverpod 3 · go_router · the existing `vendor360_ui`
design system and dependency-free `vendor360_core`.

**Spec:** [`docs/superpowers/specs/2026-08-31-two-sided-marketplace-design.md`](../specs/2026-08-31-two-sided-marketplace-design.md)

## Global Constraints

- `vendor360_core` keeps **zero dependencies**; `vendor360_ui` never imports app
  models or networking. These boundaries are load-bearing and must survive.
- New tables use `GUID` pks defaulting to `uuid4`, `TZDateTime` timestamps,
  `JSONColumn` for blobs — Postgres semantics on a SQLite target.
- Every distributor-side query is scoped by `supplier_id` resolved **from the
  token**, never from the request body.
- `current_vendor` keeps its exact existing signature; it gains a role assertion
  only. No existing route changes behaviour.
- Backend test cases keep the `TC-` naming convention.
- Money is rendered with the existing rupee formatting; quantities use tabular
  figures.
- External dependencies stay stubbed with the real pipeline behind them. No
  payment gateway.

---

## File Structure

### Backend — create

| File | Responsibility |
|---|---|
| `app/models/distributor.py` | `DistributorUser`, `CatalogEntry`, `VendorDistributor` |
| `app/models/order.py` | `PurchaseOrder`, `PurchaseOrderLine`, `OrderEvent`, `LedgerEntry` |
| `app/services/ordering.py` | pack maths, status machine, delivery application, fill rate |
| `app/services/sourcing.py` | rank connected distributors for a shortfall |
| `app/services/distributor_intel.py` | consented demand aggregation, at-risk shops, book |
| `app/services/onboarding.py` | master catalogue, quick-add, CSV price-list parse |
| `app/api/routes/orders.py` | vendor-side orders, sourcing, connections, ledger |
| `app/api/routes/distributor.py` | everything under `/dist` |
| `app/api/routes/onboarding.py` | master catalogue + quick-add |
| `tests/test_ordering.py`, `test_sourcing.py`, `test_distributor_intel.py`, `test_connections.py`, `test_onboarding.py` | |

### Backend — modify

| File | Change |
|---|---|
| `app/core/security.py` | `role` claim, role assertion in `current_vendor`, new `current_distributor` |
| `app/api/routes/auth.py` | resolve phone across both principal tables; 409 on cross-role collision |
| `app/schemas/__init__.py` | schemas for every new payload |
| `app/models/__init__.py` | export the new tables |
| `app/main.py` | mount three new routers |
| `seed.py` | distributors, catalogues, connections, order history |

### Client — create

`packages/vendor360_core/lib/src/values/pack_quantity.dart` ·
`packages/vendor360_ui/lib/src/components/vendor/{order_status_chip,pack_stepper,order_timeline,reason_row}.dart` ·
`app/lib/data/{order_models,distributor_repository}.dart` ·
`app/lib/app/dist_shell.dart` ·
`app/lib/features/orders/{orders_screen,order_detail_screen,sourcing_sheet}.dart` ·
`app/lib/features/distributors/distributors_screen.dart` ·
`app/lib/features/dist/{today,orders,demand,catalog,shops}_screen.dart` ·
`app/lib/features/onboarding/setup_flow.dart`

### Client — modify

`app/lib/app/{providers,router,shell}.dart` · `app/lib/data/{api_client,models,repository}.dart` ·
`app/lib/features/{inventory,forecast,pools}/*` (add the Order action) ·
`app/lib/features/onboarding/onboarding_screen.dart` (role fork) ·
`app/lib/core/strings.dart`

---

## Tasks

Each task ends with its suite green.

### Task 1 — Role-aware identity
`models/distributor.py` (`DistributorUser` only), `core/security.py`,
`routes/auth.py`. Token carries `role`; `current_vendor` asserts it;
`current_distributor` mirrors it; verify resolves both tables; cross-role phone
collision returns 409.
**Gate:** `test_connections.py` — cross-role token rejection, 409 collision.

### Task 2 — Catalogue and connections
`CatalogEntry`, `VendorDistributor`. Connect freezes `scope_categories`.
**Gate:** `test_connections.py` — grant/revoke; **catalogue growth does not
widen a frozen scope**.

### Task 3 — Order model and state machine
`models/order.py`, `services/ordering.py`. Pack rounding with MOQ; validated
transitions; delivery writes `restock` Transactions idempotently.
**Gate:** `test_ordering.py` — pack maths, illegal transitions, idempotent
restock, part-fill arithmetic.

### Task 4 — Sourcing
`services/sourcing.py`. MOQ-aware landed cost, lead-vs-cover, fill rate,
distance; reasons attached.
**Gate:** `test_sourcing.py` — MOQ-aware cost beats headline unit price.

### Task 5 — Vendor order API
`routes/orders.py` + schemas + mount. Draft, place, cancel, receive, ledger,
connections, sourcing.
**Gate:** `test_ordering.py` route-level cases.

### Task 6 — Distributor API
`routes/distributor.py`. Inbox with confirm/part-fill/dispatch/deliver/reject,
catalogue CRUD, CSV import preview-then-commit, payments, pool quote.
**Gate:** part-fill round trip; pool quote fills `BargainPool.supplier_id`.

### Task 7 — Distributor intelligence
`services/distributor_intel.py` + `/dist/demand`, `/dist/vendors`,
`/dist/summary`.
**Gate:** `test_distributor_intel.py` — non-consenting vendor never appears.

### Task 8 — Onboarding
`services/onboarding.py`, `routes/onboarding.py`. Master catalogue, quick-add,
CSV parse with per-row validation.
**Gate:** `test_onboarding.py`.

### Task 9 — Seed
`seed.py` extended so every new screen has believable data on first run.
**Gate:** `python seed.py --reset` succeeds; full backend suite green.

### Task 10 — Core value object
`PackQuantity` in `vendor360_core`, zero dependencies.
**Gate:** `dart test`.

### Task 11 — Design-system components
`OrderStatusChip`, `PackStepper`, `OrderTimeline`, `ReasonRow` in
`vendor360_ui`, tokens only, no app imports.
**Gate:** `flutter test` in the package.

### Task 12 — Client data layer
Order/distributor models, API client methods, repository, offline-queued order
placement via `client_event_id`.
**Gate:** `flutter test`.

### Task 13 — Role-aware routing
`Principal` in `sessionProvider`, three-state redirect, `DistShell`.
**Gate:** app builds; vendor flow unchanged.

### Task 14 — Vendor order screens
Sourcing sheet, cart, orders list, order detail with timeline, distributors
screen. Order action wired into inventory, forecast and pools rows.
**Gate:** widget tests for three states each.

### Task 15 — Distributor screens
Today, Orders, Demand, Catalog, Shops.
**Gate:** widget tests.

### Task 16 — Onboarding fork and guided setup
Role fork, then language → categories → tap SKUs → connect distributors.
**Gate:** widget test; under two minutes to a usable catalogue.

### Task 17 — Full verification
Every suite green; app runs; screenshots of both shells.
