"""Controls for the demo pulse.

Separate from every other route file because what lives here is categorically
different: these endpoints exist to manufacture and then remove data. Keeping
them in their own file means the one part of the API that fabricates is the one
part you can read in isolation.

Unauthenticated, deliberately. They are inert unless `DEMO_MODE=1` and the
database is SQLite, and requiring a vendor token to pause a demo would mean
signing in on the machine running the presentation.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ...core.db import get_db
from ...schemas import DemoStatusOut, DemoSweepOut
from ...services.demo_pulse import count_demo_sales, pulse, sweep_demo_sales

router = APIRouter(prefix="/demo", tags=["demo"])


def _status(db: Session) -> DemoStatusOut:
    permitted, reason = pulse.permitted()
    return DemoStatusOut(
        available=permitted,
        running=pulse.running,
        reason=reason,
        sales_emitted=pulse.sales_emitted,
        demo_rows=count_demo_sales(db),
    )


@router.get("/pulse", response_model=DemoStatusOut)
def status(db: Session = Depends(get_db)):
    """Whether simulated activity is available, and whether it is running."""
    return _status(db)


@router.post("/pulse/start", response_model=DemoStatusOut)
async def start(db: Session = Depends(get_db)):
    # `async` is load-bearing: a sync handler runs in a threadpool with no
    # event loop, and `asyncio.create_task` there raises rather than starting
    # anything.
    started, reason = pulse.start()
    if not started:
        # 409 rather than 403: nothing is forbidden, the server is simply not
        # in a state where this means anything.
        raise HTTPException(status_code=409, detail=reason)
    return _status(db)


@router.post("/pulse/stop", response_model=DemoStatusOut)
async def stop(db: Session = Depends(get_db)):
    await pulse.stop()
    return _status(db)


@router.delete("/pulse/sales", response_model=DemoSweepOut)
async def sweep(db: Session = Depends(get_db)):
    """Remove every fabricated sale, leaving the seeded world as it was.

    Stops the pulse first — sweeping while it is still writing would leave
    rows created between the delete and the next tick.
    """
    await pulse.stop()
    removed = sweep_demo_sales(db)
    return DemoSweepOut(
        removed=removed,
        note="Stock levels are not rewound. Re-run seed.py --reset for a "
        "clean world.",
    )
