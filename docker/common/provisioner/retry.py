from __future__ import annotations

import random
import time
from collections.abc import Callable
from typing import TypeVar

T = TypeVar("T")


class RetryableError(RuntimeError):
    """Error type for transient operations that may be retried."""


def run_with_retry(
    fn: Callable[[], T],
    *,
    retries: int = 3,
    base_seconds: float = 1.0,
    max_seconds: float = 30.0,
    retryable: tuple[type[BaseException], ...] = (RetryableError,),
    sleep: Callable[[float], None] = time.sleep,
) -> T:
    attempts = max(1, retries + 1)
    last_error: BaseException | None = None
    for attempt in range(1, attempts + 1):
        try:
            return fn()
        except retryable as exc:
            last_error = exc
            if attempt >= attempts:
                break
            delay = min(max_seconds, base_seconds * (2 ** (attempt - 1)))
            delay += random.uniform(0, min(0.25, delay / 4))
            sleep(delay)
    assert last_error is not None
    raise last_error
