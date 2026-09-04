# Vendor360

AI-powered predictive intelligence for India's local vendors.

A kirana store's backend turned from passive record-keeping into active
prediction: forecast what will sell, log stock by speaking, scan a receipt
instead of typing it, keep working with no signal, and build the operating
record a lender cannot otherwise see.

And then the other half — because a prediction nobody can act on is a
newsletter. Distributors are real accounts with price lists and an order
inbox, so *"you will run out of atta on Thursday"* ends in a delivery rather
than a phone call. The same forecasting engine, pointed at a wholesaler's
vendor book instead of one shop, tells them what to load on the van and which
shops run out before they can reach them.

Implements the project's PRD, TRD, Test Plan and UI/UX Design Guide.

---

## Running it

Two processes: the FastAPI backend and the Flutter client.

### 1. Backend

```bash
cd backend
python -m pip install -r requirements.txt
```

Seed a demo world — 40 stores across 8 Pune localities, 90 days of sales
shaped by weekday rhythm, salary week, festivals and monsoon:

```bash
python seed.py --reset
```

```bash
python -m uvicorn app.main:app --reload --port 8010
```

Interactive API docs at <http://127.0.0.1:8010/docs>.

### 2. Client

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8010
```

For Android, `10.0.2.2` is the emulator's route to the host:

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:8010
```

Two accounts to sign in with. There is no SMS gateway in the prototype, so the
OTP is returned by the request endpoint and shown on screen.

| Phone | Signs in as |
|---|---|
| `9876510000` | **Kumar General Stores** — the shop |
| `9820010009` | **Viman Nagar Cash & Carry** — the distributor |

The seed prints both, and picks the distributor with the fullest order book
rather than whichever was created first — an account with nothing waiting and
nobody running low makes the console look broken rather than calm.

The role is a property of the account, not of the sign-in form, so the same
screen serves both and the app builds whichever shell the server resolves.

### Tests

```bash
cd backend && python -m pytest -q
```

```bash
cd app && flutter test
```

```bash
cd packages/vendor360_ui && flutter test
```

```bash
cd packages/vendor360_core && dart test
```

383 tests across the four suites. The backend cases are named for the Test
Plan's `TC-` identifiers.

---

## Layout

```
backend/            FastAPI — business logic and the ML services
  app/models/       SQLAlchemy, written to Postgres semantics
  app/services/     forecasting · safety_stock · health_score · nlp_parser
                    ocr_parser · sync · pooling · heatmap · signals
                    ordering · sourcing · distributor_intel · connections
                    onboarding · event_bus · audiences · detectors
                    notifier · reactions · forecast_cache
  seed.py           the demo world every screen is computed from

packages/
  vendor360_ui/     design system — tokens, theme, motion, components
                    Inter for Latin, Noto Sans Devanagari behind it
  vendor360_core/   domain model, pure Dart, zero dependencies

app/                the Flutter client — one binary, two shells
  lib/data/         API client, offline queue, repositories
  lib/features/     the shop's screens, and the wholesaler's under dist/
```

`vendor360_core` has no dependencies at all, and `vendor360_ui` never imports
app models or networking. Those two boundaries are what keep the design system
reusable and the domain rules stated once.

---

## How the hard parts work

**Forecasting** blends a learned model with declared domain knowledge, because
of a data limit rather than a preference. A kirana store has ~90 days of
history, and Diwali happens once a year — so a model fitted on that data has
never observed one and cannot learn its effect at any amount of tuning. A
gradient-boosted regressor learns what the data *can* teach (weekday rhythm,
level, short trend) while festival and weather effects are applied as explicit
multipliers. That split also makes every prediction attributable, which is what
lets the app say *"+38% — Janmashtami in 3 days"* instead of a bare number.

**Safety stock** follows the classical `Z · σ · √L` formula with one departure:
perishability caps the result, on both the reorder trigger *and* the order-up-to
quantity. Capping only the trigger would refuse to hold more than three days of
milk and then order four and a half days of it.

**Offline sync** treats the device as the source of truth for in-progress work.
Quantities merge additively, so two devices offline on the same item both count;
last-write-wins applies only to scalar fields, and the losing edit is kept for
review rather than discarded. A client-generated event id per action makes an
interrupted batch safe to retry whole.

**The Health Score** is rule-based and transparent, not fitted. With no
repayment outcomes to train against, a learned model would encode guesses behind
a veneer of objectivity; stated weights (40% consistency, 40% turnover, 20%
waste) can at least be argued with and revised when pilot data arrives. The
breakdown is always returned, and thin history reports as provisional rather
than as a falsely precise number.

**The heatmap** only emits a cell once at least three stores contribute to it,
so no individual shop's sales are exposed to a competitor or a distributor.

**The order loop** is what turns every prediction into a transaction. Wholesalers
sell cases, not units, so a 12 kg shortfall against a 10 kg case is two cases and
20 kg — the rounding is computed once in `PackQuantity` and *shown* to the vendor
rather than applied silently at the doorstep. Orders carry three quantities
(ordered, confirmed, delivered) because part-fills are the norm in Indian
wholesale; collapsing them to one number would destroy the fill rate, which is
the most useful thing a shop can know about a supplier and the signal
`sourcing.py` ranks on.

**Forecasts are cached, once a day.** The `Forecast` table existed from the
first commit and nothing wrote to it; every read refitted a gradient-boosted
regressor. Invisible for one shop looking at one item, and fatal for the
distributor outlook, which fits a model per shop × SKU — measured at 10.4
seconds against a seeded book, past the client's read timeout, so the screen
fell back to an empty outlook and told a wholesaler with fifteen shops that
they had none. Writing through to that table takes it to 0.12s. The cache key
is the date, because a day's sales are only complete when the day is.

**Realtime** is an enhancement over the pull path, never a replacement for it.
A `/live` WebSocket carries hints — *something changed* — and the client
re-reads through its ordinary path, so there stays exactly one way data
arrives and a dead socket costs liveness rather than correctness. Which mode
you are in is on screen, because a display that has silently stopped updating
looks identical to a quiet afternoon.

**Three detectors** run on every stock movement. Stockout is edge-triggered on
the crossing, because level-triggered re-fires on every subsequent sale and
teaches people to swipe alerts away. Anomaly compares today against the
trailing *same-weekday* distribution — Saturdays against Saturdays, since the
weekend lift would otherwise flag every Saturday — and cannot use the forecast
cache, which holds no value for today by design. Surge opens a group order when
three shops in a locality go short of the same SKU inside six hours.

**A live event passes the same consent gate as the pull path.** Entitlement is
computed at publish time by code that can read the frozen scope, and a
distributor outside it gets no alert row either — filtering only the socket
would leave the same leak arriving more slowly.

**Distributor visibility** is a connection-scoped consent, frozen at the moment
it is granted. Computing the scope live from the wholesaler's catalogue would
mean a grain trader could add `dairy` to their price list tomorrow and silently
acquire visibility into a shop's milk forecasts. Widening it takes a second act
of consent by the vendor, and `test_connections.py` asserts exactly that. The
aggregate demand a distributor sees keeps the heatmap's k-anonymity floor: fewer
than three contributing shops and the line is suppressed, because two shops'
"total" is one shop's numbers wearing a disguise.

---

## Deliberate departures from the documents

Each of these is a substitution with the same semantics, not a dropped
requirement.

| Document says | Built as | Why |
|---|---|---|
| Prophet | scikit-learn gradient boosting | Prophet compiles a Stan backend and is fragile on current Python. Same feature semantics (seasonality + holiday regressors) behind a stable interface; swapping it in means changing `_fit_base_model` and nothing that calls it. |
| Supabase Postgres | SQLite, Postgres-compatible models | Runs with no external service. UUID/JSONB/timestamptz are handled by portable column types, so moving is a `DATABASE_URL` change, not a migration. |
| SQLite on device (drift/sqflite) | `shared_preferences` | The one durable store that behaves identically on Android and Flutter web. The queue holds tens of events, not a dataset; TC-S04's actual requirement — surviving a relaunch — is unaffected. |
| Bhashini ASR | stubbed capture | Needs credentials this prototype does not have. Everything downstream — parsing, confidence, correction, commit — is the real pipeline; only `_capture` would be replaced. |
| Camera + OCR engine | sample receipts | Same: the parser, confidence flagging, total reconciliation and expiry computation are the production path. |
| UPI / payment rail | a recorded ledger | The khata is real — charges on delivery, payments, terms, ageing and overdue netting. Settlement is the one step that needs a gateway and a licence, so recording a payment is a manual act by either side, which is also what most of this trade looks like today. |

The design system is forked from **CarryO**, keeping its structure wholesale —
semantic tokens with one file permitted to hold colour literals, Inter with
tabular figures, the 4pt scale, motion resolved against reduce-motion, and a
soft shadow in light against a hairline in dark — and re-skinned to this
project's teal and saffron.
