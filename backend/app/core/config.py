"""Runtime configuration.

`DATABASE_URL` is the only setting that must change to move from local
development to the Supabase Postgres the TRD specifies. The models are written
to Postgres semantics (UUID keys, JSON columns, timezone-aware timestamps), so
that swap is a connection-string change and not a migration.
"""
from __future__ import annotations

import os
from functools import lru_cache


class Settings:
    """Environment-backed settings.

    Read through `get_settings()` so tests can clear the cache and point the
    app at a scratch database without mutating module state.
    """

    def __init__(self) -> None:
        self.app_name: str = "Vendor360 API"
        self.database_url: str = os.getenv(
            "DATABASE_URL", "sqlite:///./vendor360.db"
        )
        # Dev-only default. In deployment this must come from the environment;
        # a shared secret in source would let anyone mint a vendor's token.
        self.jwt_secret: str = os.getenv("JWT_SECRET", "dev-secret-change-me")
        self.jwt_algorithm: str = "HS256"
        self.access_token_minutes: int = int(
            os.getenv("ACCESS_TOKEN_MINUTES", "10080")  # 7 days
        )
        # Vendors work behind a counter for hours; a short expiry would sign
        # them out mid-shift, which for this audience means abandoning the app.

        self.otp_ttl_seconds: int = int(os.getenv("OTP_TTL_SECONDS", "300"))
        # Phase I has no SMS gateway. The OTP is returned by the request
        # endpoint so the prototype is demonstrable; `expose_otp` is the single
        # flag that must be false before this ever faces a real vendor.
        self.expose_otp: bool = os.getenv("EXPOSE_OTP", "1") == "1"

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
