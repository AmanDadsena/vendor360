"""Lenders and the consent that gates score sharing (PRD 7, TC-H03)."""
from __future__ import annotations

import uuid

from sqlalchemy import Boolean, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from ..core.db import GUID, Base, TZDateTime, utcnow


class Lender(Base):
    __tablename__ = "lenders"

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(160))
    kind: Mapped[str] = mapped_column(String(30), default="nbfc")  # nbfc|mfi|bank
    contact: Mapped[str | None] = mapped_column(String(120), nullable=True)
    created_at = mapped_column(TZDateTime, default=utcnow)


class ScoreConsent(Base):
    """Explicit, revocable permission for one lender to see one vendor's score.

    Absence of a row means no access. The PRD treats data-sharing hesitancy as
    a named risk, so consent is modelled as its own auditable record rather
    than a boolean on the vendor: `granted_at` and `revoked_at` make the
    history answerable.
    """

    __tablename__ = "score_consents"
    __table_args__ = (UniqueConstraint("vendor_id", "lender_id", name="uq_consent_pair"),)

    id: Mapped[uuid.UUID] = mapped_column(GUID, primary_key=True, default=uuid.uuid4)
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("vendors.id", ondelete="CASCADE"), index=True
    )
    lender_id: Mapped[uuid.UUID] = mapped_column(
        GUID, ForeignKey("lenders.id", ondelete="CASCADE"), index=True
    )
    granted: Mapped[bool] = mapped_column(Boolean, default=False)
    granted_at = mapped_column(TZDateTime, nullable=True)
    revoked_at = mapped_column(TZDateTime, nullable=True)
    created_at = mapped_column(TZDateTime, default=utcnow)
