# Udhaar, reports, charts, speech and scanning — design

*2026-09-24*

Five slices, in build order. Each is independently useful and independently
testable; each ends in a working screen or a working endpoint, not a
half-wired abstraction.

---

## 1. Udhaar — the customer credit book

### Why

A kirana shop's ledger has two halves. Vendor360 has only ever modelled one
of them: what the shop owes its distributor. The other half — what the
neighbourhood owes the shop — is the half shopkeepers actually keep on paper,
and the reason Khatabook and OkCredit exist. A shop that can see who owes it
₹4,320, and how old that money is, is looking at its own working capital.

It also completes the Health Score's story. The score already rewards
consistency and turnover; receivables are the other thing a lender asks
about. This slice records them honestly; whether they enter the score is a
later decision, deliberately not taken here.

### Data

Two tables, both vendor-scoped:

```
customers            id, vendor_id, name, phone?, created_at
udhaar_entries       id, vendor_id, customer_id, kind, amount, note?,
                     transaction_id?, occurred_at, created_at
```

`kind` is `credit` (goods taken, money owed) or `payment` (money returned).
Balance is `sum(credit) − sum(payment)`, never stored: a stored balance and a
list of entries are two sources of truth that drift, and the entries are the
ones a customer will argue with.

`transaction_id` is nullable and optional. When a sale is logged on credit it
points at the sale, so the shop can answer "what was that ₹300 for".

`phone` is nullable. A shopkeeper who writes "Suresh, corner house" in a paper
khata should not be blocked by a form demanding a mobile number.

### Service — `app/services/udhaar.py`

- `record(db, vendor, customer, kind, amount, …)` — one entry, amount > 0.
- `balances(db, vendor)` — every customer with a non-zero balance, plus their
  oldest unpaid charge, ordered oldest-first. Oldest-first because that is the
  one a shopkeeper should chase, not the largest.
- `statement(db, vendor, customer)` — entries newest-first with a running
  balance, and what the customer owes now.
- `totals(db, vendor)` — outstanding, number of customers owing, and the
  oldest debt in days.

Payments settle **oldest debt first**, the same rule `ordering.summarise_ledger`
already applies to the distributor ledger. Two ledgers in one product that
settle differently would be a bug nobody could see.

### API — `app/api/routes/udhaar.py`

| Method | Path | Returns |
|---|---|---|
| GET | `/udhaar` | totals + customers with balances |
| POST | `/udhaar/customers` | create a customer |
| GET | `/udhaar/{customer_id}` | that customer's statement |
| POST | `/udhaar/{customer_id}/entries` | record credit or payment |

All vendor-scoped through `current_vendor`; a distributor token gets 403, and
one shop can never read another's customers. That is asserted in a test, not
assumed.

### App

- `/udhaar` — customers with balances, oldest first, each row a name, what
  they owe, and how long it has been owed. A total on the band.
- `/udhaar/{id}` — the statement, with "took goods" and "paid" actions.
- Home gains one ruled line: total outstanding and how many customers, linking
  in. It sits with the money, above the places grid.
- **Remind** composes the message a shopkeeper would send —
  *"Namaste Suresh, ₹320 is pending at Kumar General Stores since 12 Sept."* —
  and hands it to `share_plus`, which opens WhatsApp on Android and the share
  sheet on the web. No message is ever sent by the app itself.

---

## 2. Day close and exports

### Why

The demo can show a day starting. It cannot yet show one ending, and "what did
today come to" is the question a shopkeeper asks last thing. A lender or an
accountant then wants that on paper, which the app cannot produce at all.

### Endpoints — `app/api/routes/reports.py`

| Path | Produces |
|---|---|
| `GET /reports/day-close?on=` | JSON: sales, entries, top items, wastage, udhaar given and collected, what is low |
| `GET /reports/day-close.pdf?on=` | the same as a one-page day sheet |
| `GET /reports/credit.pdf` | the existing credit assessment as a lender-ready PDF |
| `GET /reports/ledger.xlsx` | a workbook: transactions, stock, udhaar |

`reportlab` draws the PDFs, `openpyxl` the workbook. Both are added to
`requirements.txt` with the same upper bounds as the rest of the stack.

The PDFs carry the same discipline as the screens: the figures are the
server's own, the day is named, and a provisional score says so on the page.
A PDF that looks official is exactly where an unlabelled estimate does harm.

### App

A **Day close** screen off Home: the day's summary in the same ruled
declaration style, then Download day sheet / Download ledger / Share credit
report, opened with `url_launcher`.

---

## 3. Charts

### Why

Three screens currently describe trends in words and one hand-drawn sparkline.
A shopkeeper deciding whether this week is better than last should see it.

`fl_chart` is the library, themed to the printed-pack world: flat teal bars,
ink axis labels, no chart junk, no gradients, tabular figures. A chart here is
a printed panel, not a dashboard widget.

- **Sales trend** — 14 daily bars, on Day close and on the Score screen, from
  a new `GET /reports/sales-series?days=`.
- **Forecast accuracy** — predicted against actual on the Accuracy screen,
  which today reports a single MAPE number.

The dataviz rules apply: one colour per meaning, no rainbow, labels that name
their units, and never a pie chart for something ordered.

---

## 4. Real speech-to-text

`speech_to_text` replaces `_capture`'s sample sentences. The locale follows the
app's language (`hi-IN`, `mr-IN`, `en-IN`). Where no engine exists — a browser
without the API, a device that refuses the permission — the screen says so
plainly and falls back to the samples, because a demo that cannot speak must
still be able to show the pipeline.

Nothing downstream changes: the transcript still goes to the same parser, the
same confirm step, the same commit. That was the point of the original seam.

## 5. Barcode and camera

`mobile_scanner` reads a pack's barcode and logs the sale; `image_picker`
takes a receipt photo instead of choosing a bundled sample. Both need a
`barcode` column on inventory and the catalogue, with EAN-13s seeded for the
demo SKUs, and a `GET /inventory/by-barcode/{code}` lookup.

Both are device features. On a desktop browser they are unavailable, and the
screens must say that rather than appearing broken — the same rule the voice
fallback follows.

---

## Testing

- Backend: pytest per service and route — balances and oldest-first ordering,
  payment settlement, cross-vendor isolation, the day-close arithmetic, and
  smoke tests that the PDF and XLSX endpoints return the right content type
  and a non-empty body.
- App: widget tests for the udhaar list, statement and day-close screens
  against the offline seeded world, as the other screens have.
- Design: new components go in `vendor360_ui` with tests, and follow
  `DESIGN.md` — ruled lists, status squares, declaration strips, no new
  vocabulary.

## Deliberately not in scope

- Receivables entering the Health Score. It would change what the score means,
  and that deserves its own decision.
- Reminders sent by the app (SMS/WhatsApp API). The app composes; the
  shopkeeper sends. Anything else needs consent plumbing this does not have.
- Payments/UPI collection. Out of scope for a prototype that takes no money.
