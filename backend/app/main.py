from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
import firebase_admin
from firebase_admin import credentials
import os

from app.config import settings
from app.database import init_db, close_db
from app.routers import auth, users, conversations, calls, translation, admin
from app.websocket.handlers import websocket_endpoint
from app.middleware.rate_limit import RateLimitMiddleware
from app.middleware.logging import RequestLoggingMiddleware, configure_logging


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    configure_logging(debug=settings.DEBUG)
    import logging
    logging.getLogger("app").info(
        "Starting %s v%s (debug=%s)", settings.APP_NAME, settings.APP_VERSION, settings.DEBUG
    )

    # Initialize Firebase
    cred_path = settings.FIREBASE_CREDENTIALS_PATH
    log = logging.getLogger("app")
    if os.path.exists(cred_path) and not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        log.info("Firebase initialized")
    else:
        log.info("Firebase credentials not found - Firebase features disabled")

    # Initialize DB
    await init_db()
    log.info("Database connected")

    yield

    # Shutdown
    await close_db()
    log.info("Application shutdown")


app = FastAPI(
    title="Ubumwe Connect API",
    description=(
        "AI-powered real-time multilingual communication platform. "
        "Bringing People Together Beyond Language. "
        "Supports: Kinyarwanda, English, French, Swahili."
    ),
    version=settings.APP_VERSION,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
    lifespan=lifespan,
)

# ─── Middleware ────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.get_cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.get_trusted_hosts())
app.add_middleware(GZipMiddleware, minimum_size=1024)
app.add_middleware(RateLimitMiddleware)
app.add_middleware(RequestLoggingMiddleware)  # added last = runs first

# ─── Routers ──────────────────────────────────────────────────
API_PREFIX = "/api/v1"

app.include_router(auth.router, prefix=API_PREFIX)
app.include_router(users.router, prefix=API_PREFIX)
app.include_router(conversations.router, prefix=API_PREFIX)
app.include_router(calls.router, prefix=API_PREFIX)
app.include_router(translation.router, prefix=API_PREFIX)
app.include_router(admin.router, prefix=API_PREFIX)


# ─── WebSocket ────────────────────────────────────────────────
@app.websocket("/ws/{user_id}")
async def ws_endpoint(
    websocket: WebSocket,
    user_id: str,
    token: str = Query(...),
):
    await websocket_endpoint(websocket, user_id, token)


# ─── Health Check ─────────────────────────────────────────────
@app.get("/health", tags=["System"])
async def health_check():
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "message": "Bringing People Together Beyond Language 🌍",
    }


@app.get("/", tags=["System"])
async def root():
    return {
        "name": "Ubumwe Connect API",
        "tagline": "Bringing People Together Beyond Language",
        "version": settings.APP_VERSION,
        "docs": "/api/docs",
        "languages": ["Kinyarwanda", "English", "French", "Swahili"],
    }


# ─── Exception Handlers ────────────────────────────────────────
@app.exception_handler(404)
async def not_found_handler(request, exc):
    return JSONResponse(status_code=404, content={"detail": "Resource not found"})


@app.exception_handler(500)
async def internal_error_handler(request, exc):
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})
