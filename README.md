# Vendor360

AI-powered predictive intelligence for India's local vendors.

A kirana store's backend turned from passive record-keeping into active
prediction: forecast what will sell, log stock by speaking, scan a receipt
instead of typing it, keep working with no signal, and build the operating
record a lender cannot otherwise see.

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

Sign in with **9876510000**. There is no SMS gateway in the prototype, so the
OTP is returned by the request endpoint and shown on screen.

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

182 tests across the four suites. The backend cases are named for the Test
Plan's `TC-` identifiers.

---

## Layout

```
backend/            FastAPI — business logic and the ML services
  app/models/       SQLAlchemy, written to Postgres semantics
  app/services/     forecasting · safety_stock · health_score · nlp_parser
                    ocr_parser · sync · pooling · heatmap · signals
  seed.py           the demo world every screen is computed from

packages/
  vendor360_ui/     design system — tokens, theme, motion, components
  vendor360_core/   domain model, pure Dart, zero dependencies

app/                the Flutter client
  lib/data/         API client, offline queue, repository
  lib/features/     eleven screens
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

The design system is forked from **CarryO**, keeping its structure wholesale —
semantic tokens with one file permitted to hold colour literals, Inter with
tabular figures, the 4pt scale, motion resolved against reduce-motion, and a
soft shadow in light against a hairline in dark — and re-skinned to this
project's teal and saffron.
