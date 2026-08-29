"""Vendor360 API entrypoint.

Layered exactly as TRD 1.1 describes: the Flutter client talks only to this
REST surface, which owns the business logic and the ML services and is the only
tier that touches the database.
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.routes import auth, capture, intelligence, inventory
from .core.config import get_settings
from .core.db import Base, engine
from .models import *  # noqa: F401,F403 - registers every table on Base.metadata


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Fine for the prototype's SQLite target. Against Supabase the schema is
    # owned by the migrations directory and this becomes a no-op.
    Base.metadata.create_all(engine)
    yield


settings = get_settings()

app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description=(
        "AI-powered predictive intelligence for India's local vendors. "
        "Demand forecasting, dynamic safety stock, vernacular voice capture, "
        "OCR receipt intake, offline-first sync, and a micro-credit Health Score."
    ),
    lifespan=lifespan,
)

# The Flutter web client is served from a different port in development, so it
# is a cross-origin caller. Credentials are not used -- the session token is
# sent in the Authorization header -- so a permissive dev origin list is safe
# here and should still be narrowed before deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(inventory.router)
app.include_router(capture.router)
app.include_router(intelligence.router)


@app.get("/health", tags=["meta"])
def health():
    """Liveness probe. Deliberately unauthenticated and dependency-free."""
    return {"status": "ok", "service": settings.app_name}


@app.get("/meta/categories", tags=["meta"])
def categories():
    """The category taxonomy, so the client never hardcodes its own copy."""
    from .services.catalog import CATEGORIES

    return [
        {
            "key": c.key,
            "label_en": c.label_en,
            "label_hi": c.label_hi,
            "label_mr": c.label_mr,
            "shelf_life_days": c.shelf_life_days,
            "rain_sensitivity": c.rain_sensitivity,
            "festival_sensitivity": c.festival_sensitivity,
        }
        for c in CATEGORIES.values()
    ]
