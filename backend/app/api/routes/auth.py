"""Phone + OTP authentication (TRD 4)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...core.config import get_settings
from ...core.db import get_db, utcnow
from ...core.security import (
    MAX_OTP_ATTEMPTS,
    ROLE_DISTRIBUTOR,
    ROLE_VENDOR,
    create_access_token,
    current_distributor,
    current_vendor,
    generate_otp,
    hash_otp,
    touch_expiry,
    verify_otp,
)
from ...models import DistributorUser, OtpChallenge, Supplier, Vendor
from ...schemas import (
    DistributorOut,
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

    # An existing account's role is a property of the account, never of what
    # the sign-in form happened to say. Only a genuinely new number consults
    # `body.role`.
    vendor = db.scalar(select(Vendor).where(Vendor.phone == phone))
    if vendor is not None:
        # Only an explicit contradiction is an error. Arriving with the default
        # role and finding an account of the other type is not the caller
        # asserting anything, so it just signs them in.
        if body.role == ROLE_DISTRIBUTOR:
            db.commit()
            raise HTTPException(
                status_code=409,
                detail="This number is already registered as a shop. "
                "Sign in as a shop, or use a different number for the business.",
            )
        if body.language_pref and body.language_pref != vendor.language_pref:
            vendor.language_pref = body.language_pref
        db.commit()
        return _vendor_token(vendor)

    distributor = db.scalar(
        select(DistributorUser).where(DistributorUser.phone == phone)
    )
    if distributor is not None:
        if body.language_pref and body.language_pref != distributor.language_pref:
            distributor.language_pref = body.language_pref
        db.commit()
        return _distributor_token(distributor)

    # First verified login creates the account. There is no separate signup
    # step: for this audience an extra form is an extra reason to give up.
    if body.role == ROLE_DISTRIBUTOR:
        created = _create_distributor(db, phone, body)
        db.commit()
        return _distributor_token(created)

    vendor = Vendor(
        name=body.name or "Vendor",
        store_name=body.store_name or "My Store",
        phone=phone,
        language_pref=body.language_pref,
        city="Pune",
        locality=body.locality,
    )
    db.add(vendor)
    db.commit()
    return _vendor_token(vendor)


def _create_distributor(db: Session, phone: str, body: OtpVerify) -> DistributorUser:
    """Register a new wholesaler and the organisation they act for.

    A distributor signing up alone gets a `Supplier` of their own. Joining an
    existing organisation is a later concern -- the schema supports it, the
    signup flow does not need to yet.
    """
    supplier = Supplier(
        name=body.business_name or body.name or "Distributor",
        kind="distributor",
        # Placed at the city centre until they set a real location. The
        # heatmap and distance ranking both tolerate an approximate pin better
        # than they tolerate a null.
        lat=18.5204,
        lon=73.8567,
        locality=body.locality or "Pune",
        city="Pune",
        categories=[],
        lead_days=2,
        min_order_value=0,
        rating=4.0,
        phone=phone,
    )
    db.add(supplier)
    db.flush()

    user = DistributorUser(
        supplier_id=supplier.id,
        name=body.name or "Distributor",
        phone=phone,
        language_pref=body.language_pref,
    )
    db.add(user)
    db.flush()
    return user


def _vendor_token(vendor: Vendor) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(vendor.id, vendor.phone, ROLE_VENDOR),
        role=ROLE_VENDOR,
        vendor=VendorOut.model_validate(vendor),
    )


def _distributor_token(user: DistributorUser) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(user.id, user.phone, ROLE_DISTRIBUTOR),
        role=ROLE_DISTRIBUTOR,
        distributor=_distributor_out(user),
    )


def _distributor_out(user: DistributorUser) -> DistributorOut:
    supplier = user.supplier
    return DistributorOut(
        id=user.id,
        supplier_id=supplier.id,
        name=user.name,
        phone=user.phone,
        language_pref=user.language_pref,
        business_name=supplier.name,
        kind=supplier.kind,
        locality=supplier.locality,
        city=supplier.city,
        lead_days=supplier.lead_days,
        min_order_value=supplier.min_order_value,
        rating=supplier.rating,
    )


@router.get("/me", response_model=VendorOut)
def me(vendor: Vendor = Depends(current_vendor)):
    return VendorOut.model_validate(vendor)


@router.get("/dist/me", response_model=DistributorOut)
def distributor_me(user: DistributorUser = Depends(current_distributor)):
    return _distributor_out(user)
