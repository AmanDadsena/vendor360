"""Phone + OTP authentication (TRD 4)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...core.config import get_settings
from ...core.db import get_db, utcnow
from ...core.security import (
    MAX_OTP_ATTEMPTS,
    create_access_token,
    current_vendor,
    generate_otp,
    hash_otp,
    touch_expiry,
    verify_otp,
)
from ...models import OtpChallenge, Vendor
from ...schemas import (
    OtpRequest,
    OtpRequestResponse,
    OtpVerify,
    TokenResponse,
    VendorOut,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/otp/request", response_model=OtpRequestResponse)
def request_otp(body: OtpRequest, db: Session = Depends(get_db)):
    settings = get_settings()
    phone = body.phone.strip()

    # Invalidate any outstanding challenge for this number, so an attacker
    # cannot keep several live codes in play and try them in parallel.
    for stale in db.scalars(
        select(OtpChallenge).where(
            OtpChallenge.phone == phone, OtpChallenge.consumed.is_(False)
        )
    ).all():
        stale.consumed = True

    code = generate_otp()
    db.add(
        OtpChallenge(
            phone=phone,
            code_hash=hash_otp(code, phone),
            expires_at=touch_expiry(settings.otp_ttl_seconds),
        )
    )
    db.commit()

    return OtpRequestResponse(
        sent=True,
        expires_in=settings.otp_ttl_seconds,
        dev_code=code if settings.expose_otp else None,
    )


@router.post("/otp/verify", response_model=TokenResponse)
def verify(body: OtpVerify, db: Session = Depends(get_db)):
    phone = body.phone.strip()

    challenge = db.scalar(
        select(OtpChallenge)
        .where(OtpChallenge.phone == phone, OtpChallenge.consumed.is_(False))
        .order_by(OtpChallenge.created_at.desc())
    )
    if challenge is None:
        raise HTTPException(status_code=400, detail="No pending code for this number")

    if challenge.expires_at < utcnow():
        challenge.consumed = True
        db.commit()
        raise HTTPException(status_code=400, detail="Code expired, request a new one")

    if challenge.attempts >= MAX_OTP_ATTEMPTS:
        challenge.consumed = True
        db.commit()
        raise HTTPException(status_code=429, detail="Too many attempts, request a new code")

    if not verify_otp(body.code, phone, challenge.code_hash):
        # Counted before the failure is returned, so the limit cannot be
        # sidestepped by abandoning the request.
        challenge.attempts += 1
        db.commit()
        raise HTTPException(status_code=400, detail="Incorrect code")

    challenge.consumed = True

    vendor = db.scalar(select(Vendor).where(Vendor.phone == phone))
    if vendor is None:
        # First verified login creates the account. There is no separate signup
        # step: for this audience an extra form is an extra reason to give up.
        vendor = Vendor(
            name=body.name or "Vendor",
            store_name=body.store_name or "My Store",
            phone=phone,
            language_pref=body.language_pref,
            city="Pune",
        )
        db.add(vendor)
        db.flush()
    elif body.language_pref and body.language_pref != vendor.language_pref:
        vendor.language_pref = body.language_pref

    db.commit()

    return TokenResponse(
        access_token=create_access_token(vendor.id, vendor.phone),
        vendor=VendorOut.model_validate(vendor),
    )


@router.get("/me", response_model=VendorOut)
def me(vendor: Vendor = Depends(current_vendor)):
    return VendorOut.model_validate(vendor)
