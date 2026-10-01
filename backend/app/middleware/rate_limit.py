"""
Simple in-memory sliding-window rate limiter middleware.

Suitable for a single-instance deployment. For multi-instance deployments
swap the storage backend for Redis (REDIS_URL is already in settings).
"""
import time
from collections import defaultdict, deque
from typing import Dict, Deque

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import settings

# Paths exempt from rate limiting (health probes, docs)
EXEMPT_PATHS = {"/health", "/", "/api/docs", "/api/redoc", "/api/openapi.json", "/metrics"}

# Stricter limits for expensive endpoints (path prefix -> max requests/min)
EXPENSIVE_PREFIXES = {
    "/api/v1/translation": settings.TRANSLATION_RATE_LIMIT_PER_MINUTE,
}


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, requests_per_minute: int = None):
        super().__init__(app)
        self.requests_per_minute = requests_per_minute or settings.RATE_LIMIT_PER_MINUTE
        self._requests: Dict[str, Deque[float]] = defaultdict(deque)

    def _limit_for_path(self, path: str) -> int:
        for prefix, limit in EXPENSIVE_PREFIXES.items():
            if path.startswith(prefix):
                return limit
        return self.requests_per_minute

    def _client_ip(self, request: Request) -> str:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
        return request.client.host if request.client else "unknown"

    async def dispatch(self, request: Request, call_next):
        path = request.url.path

        # WebSockets and exempt paths are not rate limited here
        if path in EXEMPT_PATHS or request.scope.get("type") == "websocket":
            return await call_next(request)

        key = f"{self._client_ip(request)}:{self._limit_for_path(path)}"
        limit = self._limit_for_path(path)
        now = time.monotonic()
        window = self._requests[key]

        # Drop entries older than 60s
        while window and now - window[0] > 60:
            window.popleft()

        if len(window) >= limit:
            retry_after = int(60 - (now - window[0])) + 1
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests. Please slow down."},
                headers={"Retry-After": str(retry_after)},
            )

        window.append(now)
        return await call_next(request)
