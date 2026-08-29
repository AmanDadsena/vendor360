"""Database engine, session factory, and the portable column types.

The TRD specifies Supabase Postgres. Development runs on SQLite so the
prototype starts with no external service. The three type decorators below are
what make one set of models serve both: each renders the native Postgres type
when connected to Postgres, and a faithful SQLite equivalent otherwise.
Without them, `uuid` and `jsonb` columns would force two divergent schemas.
"""
from __future__ import annotations

import json
import uuid
from collections.abc import Iterator
from datetime import datetime, timezone

from sqlalchemy import CHAR, DateTime, Text, TypeDecorator, create_engine
from sqlalchemy.dialects.postgresql import JSONB, UUID as PG_UUID
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings


class GUID(TypeDecorator):
    """UUID primary key, portable across Postgres and SQLite.

    Offline-first makes this load-bearing: a device with no signal must mint
    primary keys that cannot collide with another device's, so server-assigned
    sequential IDs are not an option (TRD 3, 7.1).
    """

    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(PG_UUID(as_uuid=True))
        return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if not isinstance(value, uuid.UUID):
            value = uuid.UUID(str(value))
        return value if dialect.name == "postgresql" else str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value if isinstance(value, uuid.UUID) else uuid.UUID(str(value))


class JSONColumn(TypeDecorator):
    """`jsonb` on Postgres, JSON-encoded text on SQLite."""

    impl = Text
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(JSONB())
        return dialect.type_descriptor(Text())

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return value if dialect.name == "postgresql" else json.dumps(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        if dialect.name == "postgresql" or isinstance(value, (dict, list)):
            return value
        return json.loads(value)


class TZDateTime(TypeDecorator):
    """Timezone-aware timestamps.

    SQLite discards tzinfo on write and returns naive datetimes on read, which
    would make every sync comparison between a device timestamp and a server
    timestamp silently wrong. This normalises to UTC on the way in and
    re-attaches UTC on the way out, so `created_at` means the same thing on
    both backends.
    """

    impl = DateTime
    cache_ok = True

    def load_dialect_impl(self, dialect):
        return dialect.type_descriptor(DateTime(timezone=True))

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def utcnow() -> datetime:
    """Timezone-aware now. `datetime.utcnow()` returns a naive value."""
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


_settings = get_settings()

# check_same_thread is a SQLite-only guard against cross-thread reuse; FastAPI
# serves requests from a thread pool, so it must be relaxed there and only there.
_connect_args = {"check_same_thread": False} if _settings.is_sqlite else {}

engine = create_engine(
    _settings.database_url,
    connect_args=_connect_args,
    pool_pre_ping=True,
    future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    """FastAPI dependency yielding a session that always closes."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
