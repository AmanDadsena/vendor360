# Udhaar, reports, charts, speech and scanning — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the shop the other half of its ledger (what customers owe it), a
day it can close and hand to a lender on paper, charts it can read, real
dictation, and a barcode it can scan.

**Architecture:** Two new vendor-scoped tables behind a service that never
stores a balance; a reports route that renders the server's own figures to PDF
and XLSX; `fl_chart` themed to the printed-pack world; `speech_to_text`,
`mobile_scanner` and `image_picker` behind capability checks that degrade to
what the prototype already does.

**Tech Stack:** FastAPI · SQLAlchemy 2.0 · reportlab · openpyxl · pytest ·
Flutter · Riverpod 3 · go_router · fl_chart · share_plus · url_launcher ·
speech_to_text · mobile_scanner · image_picker

**Spec:** `docs/superpowers/specs/2026-09-24-udhaar-reports-charts-design.md`

## Global Constraints

- Every new backend dependency is pinned with an upper bound at the next
  major, as the rest of `backend/requirements.txt` is.
- All new endpoints are vendor-scoped through `current_vendor`; a distributor
  token must not reach them, and one shop must never read another's rows.
- No stored balances. Balance is always derived from entries.
- Payments settle **oldest debt first**, matching `ordering.summarise_ledger`.
- All colour lives in `packages/vendor360_ui/lib/src/tokens/v360_colors.dart`;
  screens read tokens through `context.v360`. New UI follows `DESIGN.md`:
  ruled lists, declaration strips, status squares, no new vocabulary.
- Money renders through `Money.display` (rupee symbol, lakh grouping).
- Device-only features must say what is unavailable rather than appear broken.
- Backend tests are named for Test Plan `TC-` identifiers where one applies.

---

### Task 1: Udhaar tables

**Files:**
- Create: `backend/app/models/udhaar.py`
- Modify: `backend/app/models/__init__.py`
- Test: `backend/tests/test_udhaar.py`

**Interfaces:**
- Produces: `Customer(id, vendor_id, name, phone, created_at)` and
  `UdhaarEntry(id, vendor_id, customer_id, kind, amount, note, transaction_id,
  occurred_at, created_at)`; `kind` ∈ `{"credit", "payment"}`.

- [ ] **Step 1: Write the failing test**

```python
def test_tc_u01_an_entry_belongs_to_a_customer_and_a_shop(db, vendor):
    customer = Customer(vendor_id=vendor.id, name="Suresh")
    db.add(customer)
    db.flush()
    db.add(UdhaarEntry(vendor_id=vendor.id, customer_id=customer.id,
                       kind="credit", amount=320))
    db.commit()
    entry = db.scalar(select(UdhaarEntry))
    assert entry.customer_id == customer.id
    assert entry.kind == "credit"
```

- [ ] **Step 2: Run it and watch it fail** — `python -m pytest tests/test_udhaar.py -q`, expect an ImportError.
- [ ] **Step 3: Write the models** following `app/models/order.py`: `GUID`
  primary keys, `TZDateTime` timestamps, `ForeignKey(..., ondelete="CASCADE")`,
  indexes on `vendor_id` and `customer_id`. Export both from `models/__init__`.
- [ ] **Step 4: Run it and watch it pass.**
- [ ] **Step 5: Commit** — `git add backend/app/models backend/tests/test_udhaar.py`.

---

### Task 2: Udhaar service

**Files:**
- Create: `backend/app/services/udhaar.py`
- Test: `backend/tests/test_udhaar.py`

**Interfaces:**
- Consumes: `Customer`, `UdhaarEntry` from Task 1.
- Produces: `record(db, vendor, customer, kind, amount, note=None,
  transaction_id=None) -> UdhaarEntry`; `balances(db, vendor) ->
  list[CustomerBalance]` where `CustomerBalance` is a dataclass
  `(customer, owed: float, oldest_on: datetime | None, days_outstanding: int)`;
  `statement(db, vendor, customer) -> Statement(entries, owed)`;
  `totals(db, vendor) -> Totals(outstanding, customers, oldest_days)`.

- [ ] **Step 1: Write the failing tests**

```python
def test_tc_u02_balance_is_credits_minus_payments(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 500)
    udhaar.record(db, vendor, customer, "payment", 200)
    assert udhaar.statement(db, vendor, customer).owed == 300


def test_tc_u03_a_payment_settles_the_oldest_debt_first(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 100,
                  occurred_at=days_ago(30))
    udhaar.record(db, vendor, customer, "credit", 100, occurred_at=days_ago(2))
    udhaar.record(db, vendor, customer, "payment", 100)
    balance = udhaar.balances(db, vendor)[0]
    assert balance.owed == 100
    # The 30-day-old charge is settled, so the age reported is the newer one.
    assert balance.days_outstanding <= 3


def test_tc_u04_a_settled_customer_leaves_the_list(db, vendor, customer):
    udhaar.record(db, vendor, customer, "credit", 100)
    udhaar.record(db, vendor, customer, "payment", 100)
    assert udhaar.balances(db, vendor) == []


def test_tc_u05_amounts_must_be_positive(db, vendor, customer):
    with pytest.raises(ValueError):
        udhaar.record(db, vendor, customer, "credit", -1)
```

- [ ] **Step 2: Run them and watch them fail.**
- [ ] **Step 3: Implement.** Balances derive from entries; oldest-first
  ordering; ages computed against `utcnow()`.
- [ ] **Step 4: Run them and watch them pass.**
- [ ] **Step 5: Commit.**

---

### Task 3: Udhaar API

**Files:**
- Create: `backend/app/api/routes/udhaar.py`
- Modify: `backend/app/schemas/__init__.py`, `backend/app/main.py`
- Test: `backend/tests/test_udhaar.py`

**Interfaces:**
- Produces: `GET /udhaar`, `POST /udhaar/customers`,
  `GET /udhaar/{customer_id}`, `POST /udhaar/{customer_id}/entries`.
  Schemas: `CustomerIn`, `CustomerOut`, `UdhaarEntryIn`, `UdhaarEntryOut`,
  `UdhaarBookOut(outstanding, customers, oldest_days, rows)`,
  `UdhaarStatementOut(customer, owed, entries)`.

- [ ] **Step 1: Write the failing tests** — a book read after two entries; a
  payment posted through the API moving the balance; a customer belonging to
  another shop returning 404; a distributor token returning 403.

```python
def test_tc_u06_one_shop_cannot_read_another_shops_customer(
        api, client_vendor, other_vendor_customer):
    response = api.get(f"/udhaar/{other_vendor_customer.id}",
                       headers=client_vendor)
    assert response.status_code == 404
```

- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement** the route module following `orders.py`'s shape, and
  include it in `main.py`.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 4: Udhaar in the client's data layer

**Files:**
- Create: `app/lib/data/udhaar_models.dart`
- Modify: `app/lib/data/marketplace_repository.dart`, `app/lib/app/providers.dart`
- Test: `app/test/udhaar_test.dart`

**Interfaces:**
- Produces: `UdhaarBook`, `UdhaarCustomer`, `UdhaarEntry`, `UdhaarStatement`;
  `udhaarBookProvider`, `udhaarStatementProvider(customerId)`;
  repository methods `udhaarBook()`, `udhaarStatement(id)`,
  `addCustomer(name, phone)`, `recordUdhaar(customerId, kind, amount, note)`.

- [ ] **Step 1: Write the failing test** — the book parses, and a read with the
  API down returns the seeded demo book rather than throwing (`withFallback`).
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement**, with demo data in `demo_data.dart` so the screen
  works offline like every other screen.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 5: Udhaar screens

**Files:**
- Create: `app/lib/features/udhaar/udhaar_screen.dart`,
  `app/lib/features/udhaar/customer_screen.dart`,
  `app/lib/features/udhaar/record_sheet.dart`
- Modify: `app/lib/app/router.dart`, `app/lib/features/dashboard/dashboard_screen.dart`,
  `app/lib/core/strings.dart`
- Test: `app/test/screens_test.dart`

- [ ] **Step 1: Write the failing widget test** — the list shows a customer, an
  amount and an age; Home shows the outstanding line.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement** with `PackHeader` (outstanding as the band figure,
  customers and oldest debt in the strip), a ruled list, `StatusMark` for
  anything older than 30 days, and a record sheet with amount and note.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 6: Remind, via the share sheet

**Files:**
- Modify: `app/pubspec.yaml` (`share_plus`), `app/lib/features/udhaar/customer_screen.dart`
- Create: `app/lib/features/udhaar/reminder.dart`
- Test: `app/test/udhaar_test.dart`

**Interfaces:**
- Produces: `String reminderMessage({shopName, customerName, owed, since, language})`.

- [ ] **Step 1: Write the failing test** — the message names the shop, the
  amount and the date, and is produced in the shop's language.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement** the composer as pure text (testable), and wire
  `Share.share` behind it. The app composes; it never sends.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 7: Day close endpoint

**Files:**
- Create: `backend/app/services/day_close.py`, `backend/app/api/routes/reports.py`
- Modify: `backend/app/schemas/__init__.py`, `backend/app/main.py`
- Test: `backend/tests/test_reports.py`

**Interfaces:**
- Produces: `summarise_day(db, vendor, on: date) -> DaySummary(sales_value,
  transaction_count, top_items, wastage_value, udhaar_given, udhaar_collected,
  low_stock_count)`; `GET /reports/day-close?on=`.

- [ ] **Step 1: Write the failing tests** — a day with two sales and one waste
  entry reports both; a day with nothing reports zeros rather than 404; udhaar
  given and collected come from that day's entries only.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 8: PDF and XLSX exports

**Files:**
- Modify: `backend/requirements.txt`, `backend/app/api/routes/reports.py`
- Create: `backend/app/services/render_pdf.py`, `backend/app/services/render_xlsx.py`
- Test: `backend/tests/test_reports.py`

**Interfaces:**
- Produces: `GET /reports/day-close.pdf`, `GET /reports/credit.pdf`,
  `GET /reports/ledger.xlsx`.

- [ ] **Step 1: Write the failing tests**

```python
def test_tc_r04_the_day_sheet_is_a_pdf(api, client_vendor):
    response = api.get("/reports/day-close.pdf", headers=client_vendor)
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"
    assert response.content.startswith(b"%PDF")


def test_tc_r06_a_provisional_score_says_so_on_the_page(api, client_vendor):
    text = pdf_text(api.get("/reports/credit.pdf", headers=client_vendor).content)
    assert "provisional" in text.lower() or "90 days" in text.lower()
```

- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Add `reportlab>=4.2,<5.0` and `openpyxl>=3.1,<4.0`, implement
  the renderers.** The PDF states the shop, the day, and where each figure
  came from; a provisional score is labelled on the page.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 9: Day close screen

**Files:**
- Create: `app/lib/features/reports/day_close_screen.dart`
- Modify: `app/pubspec.yaml` (`url_launcher`), `app/lib/app/router.dart`,
  `app/lib/app/providers.dart`, `app/lib/data/marketplace_repository.dart`
- Test: `app/test/screens_test.dart`

- [ ] **Step 1: Write the failing widget test** — the summary renders from the
  offline seeded day and the three download actions are present.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement** with the declaration strip for the day's figures, a
  ruled list of top items, and download actions opening the export URLs with
  the session token.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 10: Sales series endpoint

**Files:**
- Modify: `backend/app/api/routes/reports.py`, `backend/app/schemas/__init__.py`
- Test: `backend/tests/test_reports.py`

**Interfaces:**
- Produces: `GET /reports/sales-series?days=14` → `[{on, value, count}]`,
  oldest first, with empty days present as zeroes.

- [ ] **Step 1: Write the failing test** — fourteen points come back for a
  fourteen-day window even when the shop sold nothing on some of them.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 11: The chart component

**Files:**
- Modify: `packages/vendor360_ui/pubspec.yaml` (`fl_chart`)
- Create: `packages/vendor360_ui/lib/src/components/vendor/sales_bars.dart`
- Test: `packages/vendor360_ui/test/components/sales_bars_test.dart`

**Interfaces:**
- Produces: `SalesBars(points: List<SalesPoint>, height)` where
  `SalesPoint(label, value, highlighted)`.

- [ ] **Step 1: Write the failing test** — bars use the teal token, the axis
  labels use ink, and the highest bar is marked.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement** with `fl_chart`'s `BarChart`, themed: flat teal
  bars, no gridlines but a baseline rule, ink labels, tabular figures, tooltips
  in ink with paper text.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 12: Charts on the screens

**Files:**
- Modify: `app/lib/features/reports/day_close_screen.dart`,
  `app/lib/features/accuracy/accuracy_screen.dart`,
  `app/lib/app/providers.dart`
- Test: `app/test/screens_test.dart`

- [ ] **Step 1: Write the failing test** — the day-close screen renders a
  `SalesBars` from the series provider.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement**, including the accuracy screen's predicted-vs-actual
  comparison.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 13: Real speech-to-text

**Files:**
- Modify: `app/pubspec.yaml` (`speech_to_text`), `app/lib/features/voice/voice_screen.dart`
- Create: `app/lib/data/speech.dart`
- Test: `app/test/speech_test.dart`

**Interfaces:**
- Produces: `abstract class Speech { Future<bool> available(); Stream<String>
  listen(String locale); Future<void> stop(); }` with `DeviceSpeech` and
  `SampleSpeech` implementations, chosen by a provider.

- [ ] **Step 1: Write the failing test** — with no engine, the provider hands
  back the sample source and the screen says dictation is unavailable here.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement.** Locale follows `languageProvider`
  (`hi-IN` / `mr-IN` / `en-IN`). Partial results update the transcript field
  live; the confirm step is unchanged.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 14: Barcodes in the catalogue

**Files:**
- Modify: `backend/app/models/inventory.py`, `backend/app/models/distributor.py`,
  `backend/app/api/routes/inventory.py`, `backend/seed.py`
- Test: `backend/tests/test_inventory.py`

**Interfaces:**
- Produces: `barcode` (nullable, indexed) on `InventoryItem` and `CatalogEntry`;
  `GET /inventory/by-barcode/{code}`.

- [ ] **Step 1: Write the failing tests** — a known barcode returns its item; an
  unknown one returns 404; another shop's barcode is not visible.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement**, seeding EAN-13s for the demo SKUs.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 15: Scan and photo capture

**Files:**
- Modify: `app/pubspec.yaml` (`mobile_scanner`, `image_picker`),
  `app/lib/features/inventory/inventory_screen.dart`,
  `app/lib/features/receipt/receipt_screen.dart`
- Create: `app/lib/features/scan/scan_screen.dart`
- Test: `app/test/screens_test.dart`

- [ ] **Step 1: Write the failing test** — where no camera exists, the scan
  entry point renders an explanation instead of a black rectangle.
- [ ] **Step 2: Run and watch fail.**
- [ ] **Step 3: Implement**: scan → look up barcode → open the quick-record
  sheet for that item; receipt screen offers a photo alongside the samples.
- [ ] **Step 4: Run and watch pass.**
- [ ] **Step 5: Commit.**

---

### Task 16: Wire it into the product

**Files:**
- Modify: `app/lib/features/dashboard/dashboard_screen.dart`, `README.md`,
  `DESIGN.md` (only if a new component earns a rule)
- Test: the full suite

- [ ] **Step 1: Add Udhaar, Day close and Scan to Home's places grid.**
- [ ] **Step 2: Run every suite** — `pytest -q`, `flutter test` in `app`,
  `packages/vendor360_ui`, and `dart test` in `packages/vendor360_core`.
- [ ] **Step 3: Update the README's feature list and run it end to end.**
- [ ] **Step 4: Commit and push.**
