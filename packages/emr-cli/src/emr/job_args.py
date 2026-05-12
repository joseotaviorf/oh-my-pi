"""Merge ``--job-args`` (shell-style string) with repeatable ``--job-arg`` tokens."""

from __future__ import annotations

import shlex
from typing import Sequence


def merged_job_script_args(
    job_args_line: str | None,
    repeated_job_args: Sequence[str] | None,
) -> list[str] | None:
    """Return spark-submit argv after the PySpark URI, or ``None`` if empty.

    Order: tokens from ``job_args_line`` (via :func:`shlex.split`) first, then
    each non-empty entry from ``repeated_job_args``.
    """
    parts: list[str] = []
    if job_args_line is not None and str(job_args_line).strip():
        try:
            parts.extend(shlex.split(job_args_line, posix=True))
        except ValueError as e:
            raise ValueError(f"invalid shell-style --job-args string: {e}") from e
    if repeated_job_args:
        parts.extend(str(a).strip() for a in repeated_job_args if str(a).strip())
    return parts if parts else None
