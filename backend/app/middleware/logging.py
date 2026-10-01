"""
Structured request logging middleware + logging configuration.

Every request is logged with method, path, status code and duration.
Errors (4xx/5xx) are logged at WARNING/ERROR level.
"""
import logging
import time
import sys

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request


def configure_logging(debug: bool = False) -> None:
    """Configure root + app logging once at startup."""
    level = logging.DEBUG if debug else logging.INFO
    formatter = logging.Formatter(
        fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)

    # Quieten noisy third-party loggers
    for noisy in ("uvicorn.access", "botocore", "boto3", "s3transfer"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    # Route uvicorn's logs through the same formatter
    for name in ("uvicorn", "uvicorn.error"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.addHandler(handler)


logger = logging.getLogger("app.access")


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            duration_ms = (time.perf_counter() - start) * 1000
            logger.error(
                "%s %s -> 500 (%.1fms)",
                request.method,
                request.url.path,
                duration_ms,
                exc_info=True,
            )
            raise

        duration_ms = (time.perf_counter() - start) * 1000
        status = response.status_code
        # Skip noisy static/health logs
        if request.url.path not in ("/health", "/"):
            log = logger.warning if status >= 500 else (
                logger.info if status >= 400 else logger.debug
            )
            log(
                "%s %s -> %d (%.1fms)",
                request.method,
                request.url.path,
                status,
                duration_ms,
            )
        return response
