"""In-process pub/sub for live updates.

One responsibility: given an event with an audience, deliver it to the
connections entitled to receive it, and to no others.

The audience is not a routing convenience. Vendor360's consent model exists so
a grain wholesaler cannot see a shop's milk numbers, and a push channel that
skipped the check would be a backdoor around all of it. So entitlement is
computed *into* the event when it is published, by code that has a database
session and can read the frozen consent scope -- never at delivery time, where
a subscriber's own claims would be the only thing to go on.

In-process is the right scope for one uvicorn worker and the wrong scope for a
deployment behind several, where this becomes Redis pub/sub. The interface is
drawn so that swap changes this file and nothing that publishes to it.
"""
from __future__ import annotations

import asyncio
import uuid
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from ..core.db import utcnow

# A slow or wedged client must not hold up delivery to everyone else, so each
# subscriber gets a bounded queue and is dropped when it overflows rather than
# awaited. Sixty-four events is far more than a live screen falls behind by;
# a client that deep is not reading, it is gone.
MAX_QUEUED_EVENTS = 64


@dataclass(frozen=True)
class Audience:
    """Who is entitled to an event.

    `everyone` is reserved for data that is already safe for any authenticated
    principal to see -- currently only heatmap deltas, which carry the same
    k-anonymity floor the heatmap endpoint applies.
    """

    vendor_ids: frozenset[uuid.UUID] = frozenset()
    supplier_ids: frozenset[uuid.UUID] = frozenset()
    everyone: bool = False

    def admits(
        self,
        *,
        vendor_id: uuid.UUID | None = None,
        supplier_id: uuid.UUID | None = None,
    ) -> bool:
        if self.everyone:
            return True
        if vendor_id is not None and vendor_id in self.vendor_ids:
            return True
        if supplier_id is not None and supplier_id in self.supplier_ids:
            return True
        return False

    @staticmethod
    def just_vendor(vendor_id: uuid.UUID) -> "Audience":
        return Audience(vendor_ids=frozenset({vendor_id}))

    @staticmethod
    def of(
        vendors: Iterable[uuid.UUID] = (),
        suppliers: Iterable[uuid.UUID] = (),
    ) -> "Audience":
        return Audience(
            vendor_ids=frozenset(vendors),
            supplier_ids=frozenset(suppliers),
        )


@dataclass(frozen=True)
class DomainEvent:
    """Something happened. Deliberately a hint, not a payload of record.

    The client re-reads through its ordinary path when one of these lands, so
    the socket never becomes a second source of truth. That is what keeps a
    dead connection costing liveness rather than correctness.
    """

    kind: str  # sale | stockout | anomaly | surge | order | heatmap
    audience: Audience
    payload: dict[str, Any] = field(default_factory=dict)
    at: datetime = field(default_factory=utcnow)

    def wire(self) -> dict[str, Any]:
        """The shape a client receives. The audience is never sent."""
        return {
            "type": self.kind,
            "at": self.at.isoformat(),
            **self.payload,
        }


class Subscriber:
    """One live connection's inbox."""

    def __init__(
        self,
        *,
        vendor_id: uuid.UUID | None = None,
        supplier_id: uuid.UUID | None = None,
    ) -> None:
        self.vendor_id = vendor_id
        self.supplier_id = supplier_id
        self.queue: asyncio.Queue[DomainEvent] = asyncio.Queue(MAX_QUEUED_EVENTS)
        self.dropped = False

    def wants(self, event: DomainEvent) -> bool:
        return event.audience.admits(
            vendor_id=self.vendor_id, supplier_id=self.supplier_id
        )

    def offer(self, event: DomainEvent) -> bool:
        """Enqueue without waiting. False means this subscriber fell behind."""
        try:
            self.queue.put_nowait(event)
            return True
        except asyncio.QueueFull:
            self.dropped = True
            return False


class EventBus:
    def __init__(self) -> None:
        self._subscribers: set[Subscriber] = set()

    @property
    def size(self) -> int:
        return len(self._subscribers)

    def subscribe(self, subscriber: Subscriber) -> Subscriber:
        self._subscribers.add(subscriber)
        return subscriber

    def unsubscribe(self, subscriber: Subscriber) -> None:
        self._subscribers.discard(subscriber)

    def publish(self, event: DomainEvent) -> int:
        """Deliver to every entitled subscriber. Returns how many received it.

        Synchronous and non-blocking: publishing happens inside request
        handlers that are already holding a database transaction, and awaiting
        a socket there would hold the transaction open for as long as the
        slowest reader takes.
        """
        delivered = 0
        fallen_behind: list[Subscriber] = []

        for subscriber in self._subscribers:
            if not subscriber.wants(event):
                continue
            if subscriber.offer(event):
                delivered += 1
            else:
                fallen_behind.append(subscriber)

        # A subscriber that overflowed is not reading. Dropping it here stops a
        # crashed browser tab holding a subscription for the process lifetime.
        for subscriber in fallen_behind:
            self.unsubscribe(subscriber)

        return delivered

    def publish_all(self, events: Iterable[DomainEvent]) -> int:
        return sum(self.publish(event) for event in events)


# One bus per process. Imported rather than injected because publishing happens
# deep inside services that have no business taking a bus parameter through
# four call layers to reach the one place that needs it.
bus = EventBus()
