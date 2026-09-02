"""Purchase orders: pack arithmetic, the status machine, and delivery.

This module is where a prediction becomes a transaction. Three things live
here because they have to agree with each other:

* **Pack arithmetic.** Wholesalers sell cases. A shortfall of 12 kg against a
  10 kg case is two cases and 20 kg, not 1.2 of anything. Rounding is computed
  in one place and surfaced to the vendor rather than applied silently.
* **The status machine.** Transitions are validated here, not at the call
  site, so no route can move an order backwards however it is written.
* **Delivery application.** Receiving stock writes real `restock` transactions
  and bumps real inventory, which is what closes the loop: the delivery feeds
  the forecast that predicted the shortage.
"""
from __future__ import annotations

import math
import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.db import utcnow
from ..models import (
    ALLOWED_TRANSITIONS,
    CatalogEntry,
    InventoryItem,
    LedgerEntry,
    OrderEvent,
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
    Transaction,
    Vendor,
    VendorDistributor,
)
from .catalog import CATEGORIES


class OrderError(ValueError):
    """A domain rule was violated. Routes translate this to a 400."""


@dataclass(frozen=True)
class PackPlan:
    """What a shortfall actually costs once packs and MOQ are applied.

    Both the requested and the supplied quantity are carried so the UI can say
    "you need 12 kg — that is 2 cases of 10 kg, 20 kg, ₹840" instead of quietly
    ordering 20 and letting the vendor discover it on the doorstep.
    """

    packs: float
    pack_size: float
    qty_supplied: float
    qty_requested: float
    cost: float
    moq_applied: bool

    @property
    def surplus(self) -> float:
        return max(0.0, self.qty_supplied - self.qty_requested)


def plan_packs(
    shortfall: float, pack_size: float, pack_price: float, moq_packs: int = 1
) -> PackPlan:
    """Round a shortfall up to whole packs, then up again to the minimum order.

    Rounding up rather than to nearest is deliberate: under-ordering a
    perishable means a stockout, and a stockout costs a customer who then buys
    the whole basket somewhere else. Over-ordering costs shelf space.
    """
    if pack_size <= 0:
        raise OrderError("Pack size must be positive")

    needed = max(0.0, shortfall)
    packs = math.ceil(needed / pack_size) if needed > 0 else 0.0

    moq = max(1, int(moq_packs or 1))
    moq_applied = packs > 0 and packs < moq
    if packs > 0:
        packs = max(packs, moq)

    return PackPlan(
        packs=float(packs),
        pack_size=pack_size,
        qty_supplied=packs * pack_size,
        qty_requested=needed,
        cost=packs * pack_price,
        moq_applied=moq_applied,
    )


# ------------------------------------------------------------------- codes
def next_order_code(db: Session) -> str:
    """A short, sayable handle for an order.

    The two parties settle disputes over the phone and cannot read a UUID to
    each other. Derived from the row count and retried on collision, which is
    enough for a per-tenant volume that will never approach the keyspace.
    """
    base = db.scalar(select(func.count(PurchaseOrder.id))) or 0
    for offset in range(1, 500):
        code = f"PO-{base + offset:04d}"
        exists = db.scalar(select(PurchaseOrder.id).where(PurchaseOrder.code == code))
        if exists is None:
            return code
    raise OrderError("Could not allocate an order code")


# ------------------------------------------------------------------ create
def connection_for(
    db: Session, vendor_id: uuid.UUID, supplier_id: uuid.UUID
) -> VendorDistributor | None:
    return db.scalar(
        select(VendorDistributor).where(
            VendorDistributor.vendor_id == vendor_id,
            VendorDistributor.supplier_id == supplier_id,
        )
    )


def build_order(
    db: Session,
    *,
    vendor: Vendor,
    supplier: Supplier,
    lines: list[dict],
    note: str | None = None,
    pool_id: uuid.UUID | None = None,
    client_event_id: uuid.UUID | None = None,
) -> PurchaseOrder:
    """Assemble a draft order.

    Each incoming line either names a catalogue entry — in which case price,
    pack size and unit are read from it — or carries its own values for
    something the distributor does not list. Either way the values are
    *snapshotted* onto the line, so re-pricing the catalogue tomorrow cannot
    rewrite what this order cost.
    """
    if not lines:
        raise OrderError("An order needs at least one line")

    connection = connection_for(db, vendor.id, supplier.id)
    terms = connection.credit_terms_days if connection else 0

    order = PurchaseOrder(
        code=next_order_code(db),
        vendor_id=vendor.id,
        supplier_id=supplier.id,
        status="draft",
        payment_terms_days=terms,
        pool_id=pool_id,
        client_event_id=client_event_id,
        note=note,
    )
    db.add(order)
    db.flush()

    total = 0.0
    for raw in lines:
        line = _build_line(db, order, supplier, raw)
        total += line.line_total
        db.add(line)

    order.amount_total = round(total, 2)
    db.flush()
    _record_event(db, order, None, "draft", "vendor", vendor.id, None)
    return order


def _build_line(
    db: Session, order: PurchaseOrder, supplier: Supplier, raw: dict
) -> PurchaseOrderLine:
    entry: CatalogEntry | None = None
    entry_id = raw.get("catalog_entry_id")

    if entry_id:
        entry = db.scalar(
            select(CatalogEntry).where(
                CatalogEntry.id == entry_id,
                CatalogEntry.supplier_id == supplier.id,
            )
        )
        if entry is None:
            # Scoped to the supplier on purpose: quoting another wholesaler's
            # price line on this order would be a pricing exploit.
            raise OrderError("That item is not in this distributor's catalogue")

    sku_name = raw.get("sku_name") or (entry.sku_name if entry else None)
    if not sku_name:
        raise OrderError("Every line needs an item name")

    packs = float(raw.get("packs") or 0)
    if packs <= 0:
        raise OrderError(f"{sku_name}: quantity must be more than zero")

    pack_size = float(raw.get("pack_size") or (entry.pack_size if entry else 1) or 1)
    unit_price = raw.get("unit_price")
    if unit_price is None:
        unit_price = entry.unit_price if entry else 0.0

    category = raw.get("category") or (entry.category if entry else "staples")
    unit = raw.get("unit") or (entry.unit if entry else "pc")

    return PurchaseOrderLine(
        order_id=order.id,
        catalog_entry_id=entry.id if entry else None,
        item_id=raw.get("item_id"),
        sku_name=sku_name,
        category=category,
        unit=unit,
        pack_size=pack_size,
        unit_price=float(unit_price),
        packs_ordered=packs,
        line_total=round(packs * pack_size * float(unit_price), 2),
    )


# -------------------------------------------------------------- transitions
def transition(
    db: Session,
    order: PurchaseOrder,
    to_status: str,
    *,
    actor_role: str,
    actor_id: uuid.UUID | None = None,
    note: str | None = None,
) -> PurchaseOrder:
    """Move an order to a new status, or refuse.

    The permitted moves are declared on the model next to the statuses
    themselves, so the machine and its vocabulary cannot drift apart. Every
    accepted move writes an `OrderEvent`, which is what makes the timeline and
    any later dispute answerable.
    """
    current = order.status
    allowed = ALLOWED_TRANSITIONS.get(current, ())

    if to_status not in allowed:
        if current == to_status:
            raise OrderError(f"This order is already {current}")
        raise OrderError(f"An order that is {current} cannot become {to_status}")

    now = utcnow()
    order.status = to_status

    if to_status == "placed":
        order.placed_at = now
        order.expected_at = now + timedelta(days=_lead_days(db, order))
    elif to_status == "confirmed":
        order.confirmed_at = now
    elif to_status == "dispatched":
        order.dispatched_at = now
    elif to_status == "delivered":
        order.delivered_at = now
    elif to_status == "cancelled":
        order.cancelled_at = now

    _record_event(db, order, current, to_status, actor_role, actor_id, note)
    db.flush()
    return order


def _lead_days(db: Session, order: PurchaseOrder) -> int:
    """Longest lead time across the order's lines, falling back to the supplier.

    An order arrives when its slowest line arrives, so promising the fastest
    would be a promise the distributor cannot keep.
    """
    supplier = db.get(Supplier, order.supplier_id)
    base = supplier.lead_days if supplier else 2

    entry_ids = [line.catalog_entry_id for line in order.lines if line.catalog_entry_id]
    if not entry_ids:
        return base

    overrides = db.scalars(
        select(CatalogEntry.lead_days).where(CatalogEntry.id.in_(entry_ids))
    ).all()
    return max([base, *[d for d in overrides if d is not None]])


def _record_event(
    db: Session,
    order: PurchaseOrder,
    from_status: str | None,
    to_status: str,
    actor_role: str,
    actor_id: uuid.UUID | None,
    note: str | None,
) -> None:
    db.add(
        OrderEvent(
            order_id=order.id,
            actor_role=actor_role,
            actor_id=actor_id,
            from_status=from_status,
            to_status=to_status,
            note=note,
        )
    )


def amend_lines(
    order: PurchaseOrder, quantities: dict[uuid.UUID, float], field: str
) -> None:
    """Set `packs_confirmed` or `packs_delivered` per line, and reprice.

    A distributor who can only supply eight of the twelve cases says so here.
    The amount owed follows what was actually committed, not what was asked
    for — anything else invoices for goods that never moved.
    """
    if field not in {"packs_confirmed", "packs_delivered"}:
        raise OrderError(f"Cannot amend {field}")

    for line in order.lines:
        if line.id in quantities:
            value = max(0.0, float(quantities[line.id]))
            if value > line.packs_ordered:
                raise OrderError(
                    f"{line.sku_name}: cannot supply more than the "
                    f"{line.packs_ordered:g} ordered"
                )
            setattr(line, field, value)
        elif getattr(line, field) is None:
            # Silence means "all of it, as ordered" — the common case, and one
            # a distributor should not have to type out line by line.
            setattr(line, field, line.effective_packs)

        line.line_total = round(
            line.effective_packs * line.pack_size * line.unit_price, 2
        )

    order.amount_total = round(sum(line.line_total for line in order.lines), 2)


# --------------------------------------------------------------- delivery
def apply_delivery(db: Session, order: PurchaseOrder) -> list[Transaction]:
    """Turn a delivered order into stock on the shelf.

    Writes one `restock` transaction per line and raises the matching
    inventory row, creating it when the shop is buying something for the first
    time. This is the point at which the loop closes: what arrived becomes
    history, and the forecaster reads that history.

    Guarded on `delivered_at` so a retried request cannot restock twice — the
    same idempotency discipline the offline sync journal already uses.
    """
    written: list[Transaction] = []

    for line in order.lines:
        packs = line.packs_delivered
        if packs is None:
            packs = line.effective_packs
        qty = packs * line.pack_size
        if qty <= 0:
            continue

        item = _resolve_item(db, order.vendor_id, line)
        item.current_qty += qty
        item.last_updated = utcnow()

        # Restocking a perishable resets its countdown: what is on the shelf
        # now is the fresh delivery, not what was there yesterday.
        if item.shelf_life_days:
            item.expires_on = utcnow() + timedelta(days=item.shelf_life_days)

        txn = Transaction(
            vendor_id=order.vendor_id,
            item_id=item.id,
            type="restock",
            qty=qty,
            unit_value=line.unit_price,
            source="order",
            confidence=1.0,
            raw_text=f"{order.code} · {line.sku_name}",
        )
        db.add(txn)
        written.append(txn)

        line.item_id = item.id

    _post_charge(db, order)
    db.flush()
    return written


def _resolve_item(
    db: Session, vendor_id: uuid.UUID, line: PurchaseOrderLine
) -> InventoryItem:
    """Find the shelf this line belongs on, or open a new one."""
    if line.item_id:
        item = db.get(InventoryItem, line.item_id)
        if item is not None and item.vendor_id == vendor_id:
            return item

    item = db.scalar(
        select(InventoryItem).where(
            InventoryItem.vendor_id == vendor_id,
            func.lower(InventoryItem.sku_name) == line.sku_name.lower(),
        )
    )
    if item is not None:
        return item

    spec = CATEGORIES.get(line.category)
    item = InventoryItem(
        vendor_id=vendor_id,
        sku_name=line.sku_name,
        category=line.category,
        current_qty=0,
        unit=line.unit,
        unit_cost=line.unit_price,
        # A first sensible retail price rather than zero, so a brand-new line
        # does not report a 100% loss on its first sale. The vendor can edit it.
        unit_price=round(line.unit_price * 1.15, 2),
        shelf_life_days=spec.shelf_life_days if spec else None,
    )
    db.add(item)
    db.flush()
    return item


def _post_charge(db: Session, order: PurchaseOrder) -> None:
    """Record what is now owed for this delivery.

    One charge per order, keyed on the order id, so a replayed delivery does
    not double the debt.
    """
    existing = db.scalar(
        select(LedgerEntry.id).where(
            LedgerEntry.order_id == order.id, LedgerEntry.kind == "charge"
        )
    )
    if existing is not None:
        return

    due = utcnow() + timedelta(days=order.payment_terms_days or 0)
    db.add(
        LedgerEntry(
            vendor_id=order.vendor_id,
            supplier_id=order.supplier_id,
            order_id=order.id,
            kind="charge",
            amount=order.amount_total,
            due_on=due,
            note=f"{order.code} delivered",
        )
    )


# ---------------------------------------------------------------- analytics
def fill_rate(
    db: Session,
    supplier_id: uuid.UUID,
    *,
    vendor_id: uuid.UUID | None = None,
    minimum_orders: int = 2,
) -> float | None:
    """Delivered quantity as a fraction of ordered, across completed orders.

    Returns None rather than a number below `minimum_orders`, because one
    lucky delivery is not a track record and presenting it as 100% would rank
    an unknown supplier above a proven one.
    """
    stmt = (
        select(
            func.sum(PurchaseOrderLine.packs_delivered * PurchaseOrderLine.pack_size),
            func.sum(PurchaseOrderLine.packs_ordered * PurchaseOrderLine.pack_size),
            func.count(func.distinct(PurchaseOrder.id)),
        )
        .join(PurchaseOrder, PurchaseOrder.id == PurchaseOrderLine.order_id)
        .where(
            PurchaseOrder.supplier_id == supplier_id,
            PurchaseOrder.status == "delivered",
        )
    )
    if vendor_id is not None:
        stmt = stmt.where(PurchaseOrder.vendor_id == vendor_id)

    delivered, ordered, order_count = db.execute(stmt).one()
    if not ordered or (order_count or 0) < minimum_orders:
        return None
    return round(min(1.0, (delivered or 0) / ordered), 4)


def outstanding(
    db: Session,
    vendor_id: uuid.UUID,
    *,
    supplier_id: uuid.UUID | None = None,
) -> float:
    """Charges less payments. Positive means the shop owes the wholesaler."""
    stmt = select(LedgerEntry).where(LedgerEntry.vendor_id == vendor_id)
    if supplier_id is not None:
        stmt = stmt.where(LedgerEntry.supplier_id == supplier_id)

    balance = 0.0
    for entry in db.scalars(stmt):
        if entry.kind == "payment":
            balance -= entry.amount
        else:
            balance += entry.amount
    return round(balance, 2)


@dataclass
class LedgerSummary:
    outstanding: float
    overdue: float
    due_this_week: float
    # Per-entry: whether this charge is still unsettled past its due date.
    overdue_ids: set[uuid.UUID]


def summarise_ledger(entries: list[LedgerEntry]) -> LedgerSummary:
    """Total, overdue and imminent balances from a list of ledger entries.

    Overdue means *unpaid* and past its date, which is the only reading that
    makes sense: a charge that was late and has since been settled is history,
    not a debt. Computing it as "every charge past its due date" — the obvious
    one-line version — reports an overdue figure larger than the total owed,
    which is visibly nonsense to anyone reading the screen.

    Payments are matched to their order where one is recorded, then any
    unattributed payment is applied oldest-debt-first, which is both the
    conventional accounting treatment and the one that flatters the shop least.
    """
    charges = [e for e in entries if e.kind != "payment"]
    payments = [e for e in entries if e.kind == "payment"]

    # Attributed payments settle their own order first.
    paid_by_order: dict[uuid.UUID, float] = defaultdict(float)
    floating = 0.0
    for payment in payments:
        if payment.order_id is not None:
            paid_by_order[payment.order_id] += payment.amount
        else:
            floating += payment.amount

    remaining: list[tuple[LedgerEntry, float]] = []
    for charge in charges:
        settled = paid_by_order.get(charge.order_id, 0.0) if charge.order_id else 0.0
        applied = min(settled, charge.amount)
        if charge.order_id is not None:
            paid_by_order[charge.order_id] -= applied
        remaining.append((charge, charge.amount - applied))

    # Anything left over — a payment against no particular order, or an
    # overpayment on one — comes off the oldest debt first.
    leftover = floating + sum(max(0.0, v) for v in paid_by_order.values())
    remaining.sort(key=lambda pair: pair[0].created_at)

    settled_amounts: list[tuple[LedgerEntry, float]] = []
    for charge, owed in remaining:
        take = min(leftover, owed)
        leftover -= take
        settled_amounts.append((charge, owed - take))

    now = utcnow()
    week = now + timedelta(days=7)

    total = overdue = due_week = 0.0
    overdue_ids: set[uuid.UUID] = set()

    for charge, owed in settled_amounts:
        total += owed
        if owed <= 0.005:
            continue
        if charge.due_on is not None and charge.due_on < now:
            overdue += owed
            overdue_ids.add(charge.id)
        elif charge.due_on is not None and charge.due_on <= week:
            due_week += owed

    return LedgerSummary(
        outstanding=round(total, 2),
        overdue=round(overdue, 2),
        due_this_week=round(due_week, 2),
        overdue_ids=overdue_ids,
    )
