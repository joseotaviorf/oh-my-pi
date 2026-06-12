"""Classify validation failures for retry vs flag-only behavior."""

from __future__ import annotations

import re

_INFRA_PATTERNS = (
    re.compile(r"AccessDenied", re.I),
    re.compile(r"not authorized to perform:\s*s3:", re.I),
    re.compile(r"403 Forbidden", re.I),
)

_SYNTAX_PATTERNS = (
    re.compile(r"\[PARSE_SYNTAX_ERROR\]", re.I),
    re.compile(r"ParseException", re.I),
    re.compile(r"\[UNSUPPORTED_FEATURE", re.I),
    re.compile(r"Syntax error at or near", re.I),
    re.compile(r"missing '\)'", re.I),
    re.compile(r"missing '\('", re.I),
    re.compile(r"CANNOT_PARSE", re.I),
    re.compile(r"AnalysisException", re.I),
)

_PARITY_PATTERNS = (
    re.compile(r"count_delta", re.I),
    re.compile(r"schema=fail", re.I),
    re.compile(r"schema mismatch", re.I),
    re.compile(r"Missing column", re.I),
    re.compile(r"Extra column", re.I),
)


def is_infra_failure(error: str | None) -> bool:
    if not error:
        return False
    return any(pattern.search(error) for pattern in _INFRA_PATTERNS)


def is_emr_syntax_failure(error: str | None) -> bool:
    """True when EMR failed to parse/analyze SQL (retry-eligible)."""
    if not error:
        return False
    if is_infra_failure(error):
        return False
    if any(pattern.search(error) for pattern in _PARITY_PATTERNS):
        return False
    return any(pattern.search(error) for pattern in _SYNTAX_PATTERNS)


def is_parity_failure(error: str | None) -> bool:
    """True for count/schema/baseline mismatch FAILs (flag only, no auto-retry)."""
    if not error:
        return False
    if is_infra_failure(error) or is_emr_syntax_failure(error):
        return False
    return any(pattern.search(error) for pattern in _PARITY_PATTERNS)


def failure_retry_label(error: str | None) -> str:
    if is_emr_syntax_failure(error):
        return "yes"
    return "no"
