"""The live channel, and the alert record behind it.

Two halves of the same idea. `/live` is the fast path -- something happened,
here is a hint, re-read. `/alerts` is the record, so a shopkeeper who was
serving a customer when it happened still finds out.

The socket carries hints rather than data on purpose. If it carried state it
would be a second source of truth, and a dropped connection would leave a
screen confidently showing something stale. As a hint channel, a dead socket
costs liveness and nothing else -- which is the only way realtime and
offline-first can share an app.
"""
from __future__ import annotations

import asyncio
import uuid

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ...core.db import SessionLocal, get_db, utcnow
from ...core.security import (
    ROLE_DISTRIBUTOR,
    ROLE_VENDOR,
    current_distributor,
    current_vendor,
    decode_token,
)
from ...models import Alert, DistributorUser, Vendor
from ...schemas import AlertOut, AlertsOut
from ...services.event_bus import Subscriber, bus

router = APIRouter(tags=["live"])

# Long enough not to chatter, short enough that a browser tab closed without a
# close frame is reaped within a minute.
HEARTBEAT_SECONDS = 20

# Closing codes in the private range, so a client can tell "you are not welcome"
# from "the network died" and only retry the second.
WS_UNAUTHORISED = 4401


@router.websocket("/live")
async def live(socket: WebSocket) -> None:
    """Push events to one authenticated principal.

    The token arrives in the first frame rather than the query string. A query
    parameter would be written to every access log the request passes through,
    and a session token sitting in a log file is a credential with a long and
    unmanaged life.
    """
    await socket.accept()

    try:
        hello = await asyncio.wait_for(socket.receive_json(), timeout=10)
    except (TimeoutError, asyncio.TimeoutError, WebSocketDisconnect, ValueError):
        await socket.close(code=WS_UNAUTHORISED, reason="No credentials")
        return

    principal = _resolve(hello.get("token"))
    if principal is None:
        await socket.close(code=WS_UNAUTHORISED, reason="Invalid session")
        return

    role, vendor_id, supplier_id = principal
    subscriber = bus.subscribe(
        Subscriber(vendor_id=vendor_id, supplier_id=supplier_id)
    )

    await socket.send_json({"type": "ready", "role": role})

    try:
        while True:
            try:
                event = await asyncio.wait_for(
                    subscriber.queue.get(), timeout=HEARTBEAT_SECONDS
                )
            except (TimeoutError, asyncio.TimeoutError):
                # Doubles as liveness in both directions: if the peer is gone,
                # this send raises and the connection is cleaned up.
                await socket.send_json({"type": "ping"})
                continue

            await socket.send_json(event.wire())
    except (WebSocketDisconnect, RuntimeError):
        # RuntimeError covers a send against an already-closed transport, which
        # is an ordinary way for this loop to end rather than a fault.
        pass
    finally:
        bus.unsubscribe(subscriber)


def _resolve(
    token: str | None,
) -> tuple[str, uuid.UUID | None, uuid.UUID | None] | None:
    """Identify the principal behind a token, or None.

    Uses its own short-lived session: `get_db` is a request dependency and a
    WebSocket outlives the request that opened it, so holding that session for
    the life of the connection would pin a pooled connection for hours.
    """
    if not token:
        return None

    try:
        payload = decode_token(token)
    except HTTPException:
        return None

    try:
        subject = uuid.UUID(payload.get("sub", ""))
    except (ValueError, TypeError):
        return None

    role = payload.get("role", ROLE_VENDOR)
    db = SessionLocal()
    try:
        if role == ROLE_DISTRIBUTOR:
            user = db.get(DistributorUser, subject)
            return None if user is None else (role, None, user.supplier_id)

        vendor = db.get(Vendor, subject)
        return None if vendor is None else (role, vendor.id, None)
    finally:
        db.close()


# ------------------------------------------------------------------ alerts
def _alert_out(alert: Alert) -> AlertOut:
    return AlertOut(
        id=alert.id,
        kind=alert.kind,
        severity=alert.severity,
        title=alert.title,
        body=alert.body,
        subject_id=alert.subject_id,
        payload=dict(alert.payload or {}),
        read=alert.is_read,
        created_at=alert.created_at,
    )


def _alerts_for(db: Session, *, column, value, unread_only: bool) -> AlertsOut:
    stmt = select(Alert).where(column == value)
    if unread_only:
        stmt = stmt.where(Alert.read_at.is_(None))

    rows = db.scalars(stmt.order_by(Alert.created_at.desc()).limit(100)).all()
    unread = db.scalar(
        select(func.count(Alert.id)).where(column == value, Alert.read_at.is_(None))
    )

    return AlertsOut(
        unread=unread or 0,
        alerts=[_alert_out(a) for a in rows],
    )


@router.get("/alerts", response_model=AlertsOut)
def vendor_alerts(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
    unread_only: bool = False,
):
    return _alerts_for(
        db, column=Alert.vendor_id, value=vendor.id, unread_only=unread_only
    )


@router.post("/alerts/{alert_id}/read", status_code=204)
def mark_vendor_alert_read(
    alert_id: uuid.UUID,
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    _mark_read(db, alert_id, column=Alert.vendor_id, value=vendor.id)


@router.post("/alerts/read-all", status_code=204)
def mark_all_vendor_alerts_read(
    vendor: Vendor = Depends(current_vendor),
    db: Session = Depends(get_db),
):
    _mark_all(db, column=Alert.vendor_id, value=vendor.id)


@router.get("/dist/alerts", response_model=AlertsOut)
def distributor_alerts(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
    unread_only: bool = False,
):
    return _alerts_for(
        db,
        column=Alert.supplier_id,
        value=user.supplier_id,
        unread_only=unread_only,
    )


@router.post("/dist/alerts/{alert_id}/read", status_code=204)
def mark_distributor_alert_read(
    alert_id: uuid.UUID,
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    _mark_read(db, alert_id, column=Alert.supplier_id, value=user.supplier_id)


@router.post("/dist/alerts/read-all", status_code=204)
def mark_all_distributor_alerts_read(
    user: DistributorUser = Depends(current_distributor),
    db: Session = Depends(get_db),
):
    _mark_all(db, column=Alert.supplier_id, value=user.supplier_id)


def _mark_read(db: Session, alert_id: uuid.UUID, *, column, value) -> None:
    # Scoped by the owning column as well as the id, so a valid alert id from
    # another principal is a 404 rather than a successful write.
    alert = db.scalar(select(Alert).where(Alert.id == alert_id, column == value))
    if alert is None:
        raise HTTPException(status_code=404, detail="Alert not found")
    if alert.read_at is None:
        alert.read_at = utcnow()
        db.commit()


def _mark_all(db: Session, *, column, value) -> None:
    for alert in db.scalars(
        select(Alert).where(column == value, Alert.read_at.is_(None))
    ):
        alert.read_at = utcnow()
    db.commit()
