# Vendor360 — Live Transport, Detection, and Ease of Use

**Date:** 2026-09-03
**Status:** approved, ready for implementation
**Slices:** F (live transport + heatmap) · G (detection + alerts) · H (ease of use)

---

## The problem

Every screen in Vendor360 pulls. A shop logs a sale by voice; the distributor
watching the same locality learns about it whenever they next pull to refresh.
The heatmap is a thirty-day aggregate, so it describes last month rather than
this afternoon. And the forecasting engine, which knows what each item *should*
sell today, is never asked whether what is actually happening matches — so a
festival rush or a supply failure is visible only in hindsight.

## What this builds

1. **A live transport** that pushes change to whoever is entitled to see it, and
   a heatmap and dashboard that move as it lands.
2. **Three detectors** that turn the forecast from a daily report into something
   that notices: demand anomalies, stockout crossings, and locality surges that
   are really a group order forming.
3. **Ease-of-use features** on both sides that turn an alert into one tap.

---

## Decisions taken

| Decision | Choice | Why |
|---|---|---|
| Transport | WebSocket + in-process event bus | `uvicorn[standard]` already ships `websockets`, so the backend needs no new dependency. Sub-second latency is what makes the two-window demo legible; SSE has no clean Flutter binding, and 5s polling is visibly not realtime. |
| Push semantics | Enhancement over the pull path, never a second source of truth | The product's defining commitment is offline-first. An event says "something changed" and the client re-reads through the normal path. A dead socket costs liveness, never correctness. |
| Fallback | Polling when the socket will not connect | Keeps the offline-first guarantee literal rather than aspirational. |
| Anomaly baseline | Trailing same-weekday distribution | The forecast cache deliberately holds no value for *today* — today's sales are a partial observation, which is the whole reason the cache window opens tomorrow. Same-weekday mean ± σ is a real baseline that exists. |
| Stockout trigger | Edge, not level | Level-triggered re-fires on every subsequent sale and teaches people to ignore alerts. |
| Alerts | Persisted, then published | An alert missed because a phone was locked is worthless. The socket is the fast path; the table is the record. |
| Demo activity | None fabricated | Two browser windows is a real demonstration. A synthetic event generator would be activity that did not happen. |

---

## 1. Transport

### `GET /live` (WebSocket)

Authenticated by the existing JWT, sent as the **first frame** rather than a
query parameter — query strings are written to server access logs, and a
session token in a log file is a credential leak with a long tail.

Handshake:

1. Client connects, sends `{"token": "<jwt>"}`.
2. Server resolves the principal exactly as `current_vendor` /
   `current_distributor` do, and closes with 4401 if it cannot.
3. Server replies `{"type": "ready", "role": ..., "subscriptions": [...]}`.
4. Server pushes events until the connection drops.

Heartbeat every 20s. A client that misses two is assumed dead and cleaned up,
which stops a crashed browser tab holding a subscription forever.

### `app/services/event_bus.py`

An in-process asyncio pub/sub. One responsibility: given a `DomainEvent` with
an audience, deliver it to the connections entitled to receive it.

```python
@dataclass(frozen=True)
class Audience:
    vendor_ids: frozenset[uuid.UUID] = frozenset()
    supplier_ids: frozenset[uuid.UUID] = frozenset()
    everyone: bool = False          # k-anonymised heatmap deltas only


@dataclass(frozen=True)
class DomainEvent:
    kind: str                       # sale | stockout | anomaly | surge | order
    audience: Audience
    payload: dict
    at: datetime
```

In-process is the right scope for this prototype and the wrong scope for a
deployment behind more than one worker, where the bus becomes Redis pub/sub.
The interface is drawn so that swap changes `event_bus.py` and nothing that
publishes to it.

---

## 2. Detectors

`app/services/detectors.py`. Each is a pure function from state to zero or more
events, so each is testable without a socket, a clock, or a running server.

### `detect_anomaly(db, item, *, today)`

Compares today's cumulative sales against the trailing distribution for the
**same weekday** — Saturdays against Saturdays, because a neighbourhood shop's
Saturday looks nothing like its Tuesday and the existing seed models exactly
that lift.

Gated on elapsed day: below `MIN_DAY_FRACTION` (0.3, about 7am on a 12-hour
trading day) any number is noise and the detector stays quiet. Fires when the
z-score exceeds `ANOMALY_Z` (2.0) in either direction, and reports which way,
by how much, and what it implies for cover.

### `detect_stockout(item, *, previous_qty)`

Edge-triggered on the crossing of `reorder_point`. Takes the previous quantity
explicitly rather than reading it back, so the caller cannot accidentally
compare a value to itself after mutating it.

### `detect_surge(db, sku_name, locality, *, window_hours=6)`

Counts shops in a locality that have crossed into short on the same SKU inside
the window. At `MIN_VENDORS_FOR_POOL` (3, the constant `pooling.py` already
defines) it opens a `BargainPool` automatically rather than waiting for a
manual sweep, and emits a surge event so nearby shops and any stocking
distributor both learn about it.

---

## 3. Alerts

New `Alert` model: `id`, `vendor_id` nullable, `supplier_id` nullable, `kind`,
`severity`, `title`, `body`, `subject_id` nullable, `read_at` nullable,
`created_at`.

Written before publishing. `GET /alerts` and `POST /alerts/{id}/read` serve
both principals, scoped by the token exactly as every other route is.

---

## 4. Privacy

**A live event must pass the same consent gate as `demand_outlook`.**

A distributor receives a stockout or anomaly event for a shop only when the
connection is `active`, `shares_demand` is true, and the **frozen**
`scope_categories` cover that SKU's category. Heatmap deltas remain
k-anonymised at three contributing stores.

This is the requirement most easily lost. The consent model was built so a
grain wholesaler cannot see a shop's milk numbers; a push channel that skips
the check is a backdoor around all of it. `test_live_privacy.py` asserts the
audience computation directly — a non-consenting shop's events must reach the
shop and nobody else.

---

## 5. Client

- `data/live_connection.dart` — socket lifecycle, exponential backoff with
  jitter, heartbeat, and a `LiveStatus` of `live | reconnecting | offline`.
- `liveEventsProvider` — a broadcast stream of decoded events.
- On each event the relevant provider is invalidated. The screen re-reads
  through the ordinary path, so there is exactly one way data arrives.
- `LiveDot` in both shells. A user must be able to tell liveness from staleness
  without guessing.
- Heatmap cells animate between intensities rather than snapping, so a change
  reads as a change.
- `AlertsSheet` from both shells, with unread count on the shell.

New dependency: `web_socket_channel`.

---

## 6. Ease of use

**Vendor** — one-tap reorder from an alert · "usual order", which rebuilds the
last basket for a supplier · a **Sold out** action on any inventory row.

**Distributor** — bulk-confirm every waiting order · today's dispatch run sheet
grouped by locality · one-tap quote on a surfaced pool.

---

## 7. Testing

| File | Covers |
|---|---|
| `test_detectors.py` | weekday baseline; quiet before the day-fraction gate; **edge-triggered stockout fires once**; surge opens a pool at three and not at two |
| `test_event_bus.py` | fan-out; audience filtering; a dead subscriber is dropped rather than blocking the bus |
| `test_live_privacy.py` | **a non-consenting shop's events reach the shop and nobody else**; frozen scope still gates; k-anonymity holds on heatmap deltas |
| `test_alerts.py` | persisted before publish; read marking; cross-principal scoping |
| `live_connection_test.dart` | backoff schedule; status transitions; a dead socket still renders |

---

## Out of scope

- Redis-backed bus for multi-worker deployment (interface is ready; the
  implementation is a deployment concern)
- Push notifications to a locked device (needs FCM credentials the prototype
  does not have)
- Camera / shelf vision detection
- Any fabricated demo activity
