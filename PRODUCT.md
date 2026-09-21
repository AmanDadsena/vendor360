# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

Flutter client, Material-based, shipped to Android phones and also run as
Flutter web. Both are judged equally: it must read as a real phone app at the
counter, and hold up full-screen on a laptop during the capstone demo (the
laptop currently frames the phone layout via `AdaptiveFrame`).

## Users

- **Shop owners (vendors):** kirana store owners in Pune localities (Kothrud,
  Aundh, Viman Nagar…). On an Android phone at the counter, often one-handed,
  in daylight, between customers. Hindi is the default language; Marathi and
  English are first-class.
- **Distributors / wholesalers:** run a vendor book of shops, answer orders,
  plan the van. Same app, a separate shell resolved from the account's role.
- **Evaluators:** capstone reviewers watching a live demo on a laptop.

## Product Purpose

Turns a kirana store's record-keeping into prediction: forecast what will
sell, log stock by speaking, scan a receipt instead of typing, keep working
offline, and build the operating record (Health Score) a lender cannot
otherwise see. The distributor half closes the loop — "you will run out of
atta on Thursday" ends in an order and a delivery, not a phone call.

## Positioning

The same forecasting engine serves both sides of a wholesale relationship:
the shop sees what it will run out of; the distributor sees which shops on
its book run out before the van can reach them, under consent the shop froze
at connection time.

## Operating Context

Voice entry in Hindi/Marathi/English, OCR of paper receipts, pack-based
wholesale ordering (packs, MOQ), a ledger of dues, a live channel (WebSocket)
for alerts and the locality demand heatmap, and a clearly labelled demo mode
that simulates sales.

## Capabilities and Constraints

- Three languages; Devanagari must render everywhere (Noto Sans Devanagari is
  bundled behind the Latin face).
- Offline-first: a degraded read says less than the truth, never something false.
- All colour lives in `packages/vendor360_ui/lib/src/tokens/v360_colors.dart`;
  screens read tokens via `context.v360`.
- `vendor360_ui` carries no app models or networking.

## Brand Commitments

- Name: **Vendor360** (keep).
- **Teal is the brand colour** (keep; how it is used may change).
- **The microphone stays the centre, most prominent action** in the vendor
  bottom bar.
- Dark mode is not a commitment.
- Must not feel like a template/SaaS dashboard, must not feel playful or
  gamified, and must not feel plain like a spreadsheet or government form.

## Evidence on Hand

Seeded demo world: 40 stores across 8 Pune localities, 90 days of sales,
~120-SKU master catalogue, two demo accounts (Kumar General Stores,
Viman Nagar Cash & Carry). No real customers, testimonials or lender
partnerships exist; never invent them.

## Product Principles

1. The two-second read: the figure a shopkeeper needs is legible at arm's
   length, in sunlight, before anything decorative.
2. Speaking beats typing: voice is the primary input, never buried.
3. Honest under uncertainty: provisional, stale, offline and simulated states
   are always labelled.
4. One engine, two sides: shop and distributor see the same truth from their
   own side, within consent.

## Accessibility & Inclusion

Users with varied literacy and reading Devanagari; colour is never the only
signal (icon or label always accompanies status colour); readable in bright
daylight.
