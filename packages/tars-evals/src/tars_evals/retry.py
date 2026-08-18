"""Transient-failure retry policy shared by every model call in the harness.

Inspect retries *forever* when ``max_retries`` is unset, which is why this
package used to pin it to ``0`` at every call site. That is the opposite
extreme, and it is not free: Inspect maps ``max_retries=0`` to tenacity's
``stop_after_attempt(0)``, so the first connection blip ends the sample
immediately — wrapped in an opaque ``RetryError`` — and the sample is counted
against the gate as if the SQL were wrong.

A whole suite run was lost that way on 2026-08-17: the LiteLLM ingress dropped
mid-run, 58 of 77 samples died in the TLS handshake, and the gate reported
13% as though SQL quality had regressed. Inspect's own backoff would have
ridden straight through it.

The policy here is bounded on both axes, so a blip is absorbed without letting
a real outage stall CI:

    max_retries=6  Inspect's ``wait_exponential_jitter(initial=3)`` sleeps
                   roughly 3, 6, 12, 24, 48s between attempts — about 1.5
                   minutes of coverage for 5 retries.
    timeout=300    Hard ceiling on one request *including* its retries
                   (Inspect maps it to tenacity's ``stop_after_delay``; it is
                   NOT a per-attempt timeout, that is ``attempt_timeout``).

Both are overridable per run via ``TARS_EVAL_MAX_RETRIES`` and
``TARS_EVAL_REQUEST_TIMEOUT`` (the latter accepts a blank value or ``0`` to
mean "no ceiling"). ``TARS_EVAL_MAX_RETRIES=0`` restores the old fail-fast
behaviour.

``TARS_EVAL_RETRY_ON_ERROR`` is a separate, much more expensive knob: it
retries the *whole sample* (the entire ReAct loop, at full token cost) after
the HTTP retries above are exhausted. It stays 0 by default.
"""

from __future__ import annotations

import os
from collections.abc import Mapping

DEFAULT_MAX_RETRIES = 6
DEFAULT_REQUEST_TIMEOUT = 300
DEFAULT_RETRY_ON_ERROR = 0

_MAX_RETRIES_ENV = "TARS_EVAL_MAX_RETRIES"
_REQUEST_TIMEOUT_ENV = "TARS_EVAL_REQUEST_TIMEOUT"
_RETRY_ON_ERROR_ENV = "TARS_EVAL_RETRY_ON_ERROR"


def _env_int(name: str, default: int, env: Mapping[str, str] | None) -> int:
    """Read a non-negative int from the environment, or ``default`` if unset."""
    raw = (os.environ if env is None else env).get(name)
    if raw is None:
        return default
    raw = raw.strip()
    if not raw:
        return default
    if not raw.isdigit():
        raise ValueError(f"{name} must be a non-negative integer (got: {raw!r})")
    return int(raw)


def max_retries(env: Mapping[str, str] | None = None) -> int:
    """HTTP-level retries per model request (0 = fail on the first error)."""
    return _env_int(_MAX_RETRIES_ENV, DEFAULT_MAX_RETRIES, env)


def request_timeout(env: Mapping[str, str] | None = None) -> int | None:
    """Wall-clock ceiling for one request including retries; None = no ceiling."""
    value = _env_int(_REQUEST_TIMEOUT_ENV, DEFAULT_REQUEST_TIMEOUT, env)
    return value or None


def retry_on_error(env: Mapping[str, str] | None = None) -> int:
    """Whole-sample retries after HTTP retries are exhausted (expensive)."""
    return _env_int(_RETRY_ON_ERROR_ENV, DEFAULT_RETRY_ON_ERROR, env)


def generate_config_kwargs(env: Mapping[str, str] | None = None) -> dict[str, int]:
    """``GenerateConfig`` kwargs pinning the retry policy.

    Every ``GenerateConfig`` in this package is built with these so the subject
    model, the task-level config merged into each generate, and the judge all
    share one policy instead of drifting apart.
    """
    kwargs: dict[str, int] = {"max_retries": max_retries(env)}
    timeout = request_timeout(env)
    if timeout is not None:
        kwargs["timeout"] = timeout
    return kwargs
