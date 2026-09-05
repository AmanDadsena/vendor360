"""Simulated shop activity, so a demo moves with one person watching.

This is the only code in the project that manufactures data, and it is written
to be obvious about it. Everything else here computes from what really
happened; this invents sales that did not.

That earns three constraints:

* **Off unless asked.** `DEMO_MODE=1`, defaulted off.
* **Never against a real database.** Anything but SQLite and it refuses. A
  simulator writing fake sales into Postgres because a flag was left set is
  the failure actually worth designing against.
* **Marked.** Every row it writes carries `source="demo"`, so the fabrication
  is countable, filterable, and removable in one query. Fiction that cannot be
  told apart from data is the hazard -- not fiction as such.

It writes real transactions rather than emitting bare socket events, because
the heatmap aggregates from the database: an event with no write makes the
client re-read and receive identical numbers, so the dot blinks and nothing
moves. And because routing through the real `on_stock_changed` means the
detectors, alerts and pool formation all behave exactly as they would for a
genuine sale, rather than through a parallel path that could drift.
"""
from __future__ import annotations

import asyncio
import contextlib
import logging
import random
from datetime import datetime

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from ..core.config import get_settings
from ..core.db import SessionLocal, utcnow
from ..models import InventoryItem, Transaction, Vendor
from .detectors import DAY_CLOSES, DAY_OPENS, shop_hour
from .reactions import on_stock_changed

log = logging.getLogger(__name__)

# The marker that makes every fabricated row identifiable. `Transaction.source`
# already carries provenance (voice | ocr | manual | seed); this is one more
# value in the same vocabulary rather than a parallel flag.
DEMO_SOURCE = "demo"

# Fast enough that a watcher sees movement without waiting, slow enough that
# the numbers stay plausible. A neighbourhood shop does not sell every second.
MIN_GAP_SECONDS = 2.0
MAX_GAP_SECONDS = 5.0

# A sale is a fraction of what the item typically moves in a day, so a busy SKU
# produces bigger sales than a slow one and the heatmap shifts in proportion.
MIN_SALE_FRACTION = 0.02
MAX_SALE_FRACTION = 0.09

# How often the shop behind the demo login is the one that sells.
#
# Picking uniformly across forty shops means the demo account sees a sale
# every fortieth tick, so someone watching the vendor dashboard watches a
# still image while the heatmap moves elsewhere. Weighting the account the
# demo is actually signed into makes both screens live without making the
# aggregate implausible -- a third is a busy shop, not an impossible one.
DEMO_SHOP_BIAS = 0.34


class DemoPulse:
    """Owns the background task and the decision to run at all."""

    def __init__(self, *, rng: random.Random | None = None) -> None:
        self._task: asyncio.Task[None] | None = None
        self._rng = rng or random.Random()
        self.sales_emitted = 0

    # ------------------------------------------------------------ lifecycle
    @property
    def running(self) -> bool:
        return self._task is not None and not self._task.done()

    @staticmethod
    def permitted() -> tuple[bool, str]:
        """Whether this may run, and why not when it may not.

        Returns a reason rather than a bare bool so `/health` and the start
        endpoint can both say the same thing, and neither has to re-derive it.
        """
        settings = get_settings()
        if not settings.demo_mode:
            return False, "DEMO_MODE is not set"
        if not settings.is_sqlite:
            return (
                False,
                "refusing to fabricate sales against a non-SQLite database",
            )
        return True, "demo mode is on"

    def start(self) -> tuple[bool, str]:
        permitted, reason = self.permitted()
        if not permitted:
            log.info("demo pulse not started: %s", reason)
            return False, reason
        if self.running:
            return True, "already running"

        try:
            self._task = asyncio.create_task(self._loop())
        except RuntimeError:
            # No running loop. Only reachable if a caller invokes this from a
            # sync context; reported rather than raised so a demo control
            # cannot 500 the server.
            return False, "no running event loop to start the pulse on"

        log.warning(
            "DEMO PULSE ON — writing simulated sales marked source=%r", DEMO_SOURCE
        )
        return True, "started"

    async def stop(self) -> None:
        task = self._task
        self._task = None
        if task is None:
            return
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task

    # ----------------------------------------------------------------- loop
    async def _loop(self) -> None:
        while True:
            await asyncio.sleep(
                self._rng.uniform(MIN_GAP_SECONDS, MAX_GAP_SECONDS)
            )
            try:
                # Its own session per tick. The loop outlives any request, so
                # holding one open would pin a pooled connection for the life
                # of the process.
                db = SessionLocal()
                try:
                    if self.emit_one(db, rng=self._rng):
                        self.sales_emitted += 1
                finally:
                    db.close()
            except asyncio.CancelledError:
                raise
            except Exception:  # noqa: BLE001 - a demo must not take the app down
                log.exception("demo pulse tick failed; continuing")


def pick_target(
    db: Session, *, rng: random.Random
) -> tuple[Vendor, InventoryItem] | None:
    """A shop with something on its shelves.

    Mostly uniform, because an even spread across localities is what makes the
    heatmap move in several places rather than lighting one cell. But weighted
    towards the demo login roughly a third of the time, so the person watching
    their own dashboard sees it move too rather than only the map.
    """
    vendor_ids = db.scalars(
        select(Vendor.id).join(
            InventoryItem, InventoryItem.vendor_id == Vendor.id
        ).where(InventoryItem.current_qty > 0).distinct()
    ).all()
    if not vendor_ids:
        return None

    chosen_id = rng.choice(list(vendor_ids))
    if rng.random() < DEMO_SHOP_BIAS:
        # The first vendor created is the one seed.py prints as the demo
        # login, and the same one `_stage_demo_shop` draws down.
        demo_id = db.scalar(
            select(Vendor.id).order_by(Vendor.created_at).limit(1)
        )
        if demo_id in vendor_ids:
            chosen_id = demo_id

    vendor = db.get(Vendor, chosen_id)
    if vendor is None:
        return None

    items = db.scalars(
        select(InventoryItem).where(
            InventoryItem.vendor_id == vendor.id,
            InventoryItem.current_qty > 0,
        )
    ).all()
    if not items:
        return None

    return vendor, rng.choice(list(items))


def sale_quantity(item: InventoryItem, *, rng: random.Random) -> float:
    """A plausible single sale for this item.

    Proportional to what is on the shelf rather than a flat number, so a shop
    with 400 packets of milk sells more per transaction than one with six, and
    neither is emptied by a single tick.
    """
    fraction = rng.uniform(MIN_SALE_FRACTION, MAX_SALE_FRACTION)
    qty = item.current_qty * fraction

    # Whole units for things counted in pieces; a shop does not sell 0.4 of a
    # bar of soap.
    if item.unit in {"pc", "pkt", "btl", "dozen", "pair"}:
        qty = max(1.0, round(qty))
    else:
        qty = max(0.1, round(qty, 1))

    return min(qty, item.current_qty)


def is_trading_hours(now: datetime | None = None) -> bool:
    """Whether a neighbourhood shop would plausibly be open.

    The same window -- and the same clock -- the anomaly detector uses.
    Emitting sales at 3am would both look wrong and poison the same-weekday
    baseline the detector reads.
    """
    return DAY_OPENS <= shop_hour(now) < DAY_CLOSES


def emit_one(db: Session, *, rng: random.Random, force: bool = False) -> bool:
    """Write one simulated sale. Returns whether anything was written.

    Goes through `on_stock_changed`, the same function the real movement
    endpoint calls, so detectors fire, alerts land and pools form exactly as
    they would for a genuine sale. A parallel path would eventually drift from
    the one that matters.
    """
    if not force and not is_trading_hours():
        return False

    target = pick_target(db, rng=rng)
    if target is None:
        return False

    vendor, item = target
    qty = sale_quantity(item, rng=rng)
    if qty <= 0:
        return False

    previous_qty = item.current_qty
    item.current_qty = max(0.0, item.current_qty - qty)
    item.last_updated = utcnow()

    db.add(
        Transaction(
            vendor_id=vendor.id,
            item_id=item.id,
            type="sale",
            qty=qty,
            unit_value=item.unit_price,
            source=DEMO_SOURCE,
            confidence=1.0,
            occurred_at=utcnow(),
        )
    )
    db.commit()

    on_stock_changed(
        db,
        vendor=vendor,
        item=item,
        previous_qty=previous_qty,
        was_sale=True,
    )
    db.commit()
    return True


# Bound as a method too, so the loop and the tests call the same function.
DemoPulse.emit_one = staticmethod(emit_one)  # type: ignore[method-assign]


def count_demo_sales(db: Session) -> int:
    return db.scalar(
        select(func.count(Transaction.id)).where(
            Transaction.source == DEMO_SOURCE
        )
    ) or 0


def sweep_demo_sales(db: Session) -> int:
    """Remove every fabricated row, leaving the seeded world as it was.

    Deliberately narrow: it deletes on the marker alone, so it can never touch
    a seeded or hand-entered transaction. Stock levels are not rewound --
    reversing quantities would need per-item bookkeeping this does not keep,
    and re-running the seed is the honest way to reset the world.
    """
    removed = count_demo_sales(db)
    db.execute(delete(Transaction).where(Transaction.source == DEMO_SOURCE))
    db.commit()
    return removed


# One per process, started from the app's lifespan.
pulse = DemoPulse()
