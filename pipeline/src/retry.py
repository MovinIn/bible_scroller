"""Retry helper for transient API errors (e.g. Gemini 503 UNAVAILABLE)."""

from __future__ import annotations

import time
from typing import Callable, TypeVar

from src.config import (
    GENERATION_MAX_RETRIES,
    GENERATION_RETRY_DELAY_SECONDS,
    HTTP_RETRYABLE_STATUS_CODES,
)

T = TypeVar("T")


def is_transient_error(exc: BaseException) -> bool:
    """True when the error carries a retryable HTTP status (429/5xx)."""
    code = getattr(exc, "code", None) or getattr(exc, "status_code", None)
    if code is None:
        response = getattr(exc, "response", None)
        code = getattr(response, "status_code", None)
    return code in HTTP_RETRYABLE_STATUS_CODES


def call_with_retries(
    fn: Callable[[], T],
    *,
    description: str,
    max_retries: int = GENERATION_MAX_RETRIES,
    delay_seconds: float = GENERATION_RETRY_DELAY_SECONDS,
    sleep: Callable[[float], None] | None = None,
) -> T:
    """Call fn, retrying up to max_retries times on transient errors.

    Waits delay_seconds between attempts. Non-transient errors are raised
    immediately; the last transient error is raised once retries run out.
    """
    do_sleep = sleep if sleep is not None else time.sleep
    for attempt in range(max_retries + 1):
        try:
            return fn()
        except Exception as exc:
            if not is_transient_error(exc) or attempt == max_retries:
                raise
            print(
                f"  {description} failed with a temporary error ({exc}). "
                f"Retrying in {delay_seconds:.0f}s "
                f"(retry {attempt + 1}/{max_retries})..."
            )
            do_sleep(delay_seconds)
    raise AssertionError("unreachable")
