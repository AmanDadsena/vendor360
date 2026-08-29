"""Phone + OTP authentication and JWT session tokens (TRD 8).

OTP codes are hashed before storage with HMAC-SHA256 keyed on the app secret,
not stored in clear. `hmac.compare_digest` is used on verification so the
comparison takes the same time whatever the guess -- a plain `==` on a short
numeric code leaks it a digit at a time to anyone who can measure the response.

Row-level security is specified in the TRD as a Postgres feature. On SQLite it
cannot be enforced by the database, so `current_vendor` is the single gate every
authenticated route passes through, and every query is scoped by the vendor id
it returns. Moving to Supabase adds the database-level policy underneath this
rather than replacing it -- defence in depth, not a swap.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Vendor
from .config import get_settings
from .db import get_db, utcnow

_bearer = HTTPBearer(auto_error=False)

MAX_OTP_ATTEMPTS = 5


def generate_otp() -> str:
    """A six-digit code from a cryptographically secure source.

    `secrets` rather than `random`: the latter is seeded predictably and its
    output can be reconstructed from a few observed values.
    """
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_otp(code: str, phone: str) -> str:
    """Hash an OTP, bound to the phone number it was issued for.

    Including the phone in the message means a code hashed for one number does
    not validate for another, so a leaked hash cannot be replayed elsewhere.
    """
    secret = get_settings().jwt_secret.encode()
    return hmac.new(secret, f"{phone}:{code}".encode(), hashlib.sha256).hexdigest()


def verify_otp(code: str, phone: str, expected_hash: str) -> bool:
    return hmac.compare_digest(hash_otp(code, phone), expected_hash)


def create_access_token(vendor_id: uuid.UUID, phone: str) -> str:
    settings = get_settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(vendor_id),
        "phone": phone,
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict:
    settings = get_settings()
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


def current_vendor(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> Vendor:
    """Resolve the authenticated vendor, or reject.

    Every vendor-scoped route depends on this. Returning the ORM object rather
    than a bare id makes it awkward for a handler to accidentally query with an
    id taken from the request body instead of the token.
    """
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_token(credentials.credentials)
    try:
        vendor_id = uuid.UUID(payload.get("sub", ""))
    except (ValueError, TypeError) as exc:
        raise HTTPException(status_code=401, detail="Malformed token subject") from exc

    vendor = db.scalar(select(Vendor).where(Vendor.id == vendor_id))
    if vendor is None:
        # The token verified but its subject no longer exists — a deleted
        # vendor must not keep a working session.
        raise HTTPException(status_code=401, detail="Vendor no longer exists")

    return vendor


def touch_expiry(seconds: int) -> datetime:
    return utcnow() + timedelta(seconds=seconds)
