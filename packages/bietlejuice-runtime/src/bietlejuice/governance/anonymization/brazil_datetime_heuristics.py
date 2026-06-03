"""DATE_TIME validation and down-ranking for Presidio post-processing.

Presidio's built-in DateRecognizer is permissive. This module keeps DATE_TIME only when
the **value** matches a calendar/clock shape (primary). Column names **demote** (id_*,
*_by, document, phone) or **reinforce** compact/epoch numerics on clearly temporal columns.
"""

from __future__ import annotations

import re
from typing import Optional

from bietlejuice.governance.anonymization.brazil_document_heuristics import (
    BRAZIL_CPF_ENTITY,
    is_document_like_column,
    is_valid_cnpj,
    is_valid_cpf,
    normalize_document_digits,
)
from bietlejuice.governance.anonymization.brazil_rg_heuristics import (
    BRAZIL_RG_ENTITY,
    is_brazil_mobile_like,
    is_money_like,
    is_phone_like_column,
    is_strong_rg_column_name,
)

DATE_TIME_ENTITY = "DATE_TIME"

# Columns where DATE_TIME is semantically plausible (still requires value shape).
# ``created_by`` / ``id_created_by`` are not temporal; ``created_at`` / ``ts_created`` are.
TEMPORAL_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(?:"
    r"dt|ts|date|time|timestamp|datetime|"
    r"birth|nascimento|aniversario|dob|"
    r"valid_from|valid_to|period|reference_date|snapshot_date"
    r")(?:_|$)|"
    r"(?:^|_)(?:created|updated|modified|deleted|ingested|ingest|loaded|processed|"
    r"scheduled|expired|signed|closed|opened|started|ended)"
    r"_(?:at|date|time|timestamp)(?:_|$)|"
    r"(?:^|_)epoch_[a-z0-9_]+|"
    r".*_at$"
)

# id_* / *_id / *_by are identifiers or actor FKs, never calendar columns.
IDENTIFIER_LIKE_COLUMN_RE = re.compile(r"(?i)(?:^|_)id_[a-z0-9_]+|[a-z0-9_]+_id$|_by$")

EPOCH_VALUE_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(?:epoch|unix|timestamp|ts|time)(?:_|$)|.*_at$"
)

# Explicit calendar / clock strings (not bare integers).
_EXPLICIT_DATE_VALUE_RE = re.compile(
    r"(?i)^(?:"
    r"\d{4}[-/]\d{1,2}[-/]\d{1,2}|"
    r"\d{1,2}[-/]\d{1,2}[-/]\d{4}|"
    r"\d{4}-\d{2}-\d{2}[T ]\d{1,2}:\d{2}|"
    r"\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?|"
    r"\d{1,2}\s+(?:de\s+)?(?:jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)"
    r")"
)

_PURE_DIGITS_RE = re.compile(r"^\d+$")
_CPF_FORMATTED_IN_VALUE_RE = re.compile(r"\d{3}\.?\d{3}\.?\d{3}-?\d{2}")
_ALPHANUMERIC_VALUE_RE = re.compile(r"[A-Za-z]")

# CRM / JSON blob columns: Presidio often tags embedded timestamps as DATE_TIME.
_BUSINESS_BLOB_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(?:association|associations|properties|metadata|payload)(?:_|$)"
)


def column_demotes_date_time(column_name: Optional[str]) -> bool:
    """Column context that blocks DATE_TIME (identifiers, phones, document fields)."""
    if not column_name:
        return False
    if is_identifier_like_column(column_name):
        return True
    if is_phone_like_column(column_name):
        return True
    if is_document_like_column(column_name):
        return True
    return bool(_BUSINESS_BLOB_COLUMN_RE.search(column_name))


def is_identifier_like_column(column_name: Optional[str]) -> bool:
    """True for id_* / *_id / *_by columns (FKs and actor references, not dates)."""
    if not column_name:
        return False
    return bool(IDENTIFIER_LIKE_COLUMN_RE.search(column_name))


def is_temporal_column(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    if is_identifier_like_column(column_name):
        return False
    return bool(TEMPORAL_COLUMN_RE.search(column_name))


def _demote_entity(item: dict) -> dict:
    return {
        "type": "NOT_FOUND",
        "score": 0.0,
        "matched_value": item.get("matched_value"),
    }


def _is_plausible_epoch_value(column_name: Optional[str], digits: str) -> bool:
    if not column_name or not EPOCH_VALUE_COLUMN_RE.search(column_name):
        return False
    length = len(digits)
    return length in (10, 13)


def _is_plausible_compact_date_value(column_name: Optional[str], digits: str) -> bool:
    if not column_name or not is_temporal_column(column_name):
        return False
    return 6 <= len(digits) <= 8


def looks_like_explicit_date_value(matched_value: Optional[str]) -> bool:
    if matched_value is None:
        return False
    value = str(matched_value).strip()
    if not value or value == "SAMPLE_TOO_BIG":
        return False
    if _EXPLICIT_DATE_VALUE_RE.search(value):
        return True
    if _CPF_FORMATTED_IN_VALUE_RE.search(value):
        return False
    return False


def looks_like_non_date_value(
    column_name: Optional[str], matched_value: Optional[str]
) -> bool:
    """True when value shape is clearly not a calendar date (IDs, docs, money, CRM keys)."""
    if matched_value is None:
        return False
    value = str(matched_value).strip()
    if not value or value == "SAMPLE_TOO_BIG":
        return False
    if looks_like_explicit_date_value(value):
        return False
    if is_money_like(value):
        return True
    if _ALPHANUMERIC_VALUE_RE.search(value):
        return True
    digits = normalize_document_digits(value)
    if digits:
        if is_valid_cpf(digits) or is_valid_cnpj(digits):
            return True
        if is_brazil_mobile_like(digits):
            return True
        if _PURE_DIGITS_RE.match(value) and 6 <= len(digits) <= 15:
            if is_temporal_column(column_name) and (
                _is_plausible_epoch_value(column_name, digits)
                or _is_plausible_compact_date_value(column_name, digits)
            ):
                return False
            return True
    return False


def should_keep_date_time(
    column_name: Optional[str],
    matched_value: Optional[str],
    score: Optional[float] = None,
) -> bool:
    """Keep DATE_TIME when value matches date regex; column only demotes or reinforces."""
    del score  # Presidio score is not used; value shape is the gate.
    if matched_value is None:
        return False
    value = str(matched_value).strip()
    if not value or value == "SAMPLE_TOO_BIG":
        return False

    if column_demotes_date_time(column_name):
        return False
    if looks_like_non_date_value(column_name, value):
        return False

    if looks_like_explicit_date_value(value):
        return True

    if is_temporal_column(column_name):
        digits = normalize_document_digits(value)
        if digits and _PURE_DIGITS_RE.match(value):
            if _is_plausible_epoch_value(column_name, digits):
                return True
            if _is_plausible_compact_date_value(column_name, digits):
                return True

    return False


def apply_datetime_filter_to_cleaned_results(
    cleaned_results: list[dict],
    column_name: str,
) -> list[dict]:
    adjusted = []
    for item in cleaned_results:
        if item.get("type") != DATE_TIME_ENTITY:
            adjusted.append(item)
            continue
        if should_keep_date_time(
            column_name, item.get("matched_value"), item.get("score")
        ):
            adjusted.append(item)
        else:
            adjusted.append(_demote_entity(item))
    return adjusted


def apply_datetime_demotion_when_document_present(
    cleaned_results: list[dict],
    column_name: Optional[str] = None,
) -> list[dict]:
    """Drop DATE_TIME only when a trusted document hit shares the same sample value."""
    column = column_name or ""
    if is_temporal_column(column):
        return cleaned_results
    has_cpf = any(item.get("type") == BRAZIL_CPF_ENTITY for item in cleaned_results)
    has_trusted_rg = any(
        item.get("type") == BRAZIL_RG_ENTITY for item in cleaned_results
    ) and (is_strong_rg_column_name(column) or is_document_like_column(column))
    if not has_cpf and not has_trusted_rg:
        return cleaned_results
    adjusted = []
    for item in cleaned_results:
        if item.get("type") == DATE_TIME_ENTITY:
            adjusted.append(_demote_entity(item))
        else:
            adjusted.append(item)
    return adjusted


def apply_datetime_heuristics_to_cleaned_results(
    cleaned_results: list[dict],
    column_name: str,
) -> list[dict]:
    filtered = apply_datetime_filter_to_cleaned_results(cleaned_results, column_name)
    return apply_datetime_demotion_when_document_present(filtered, column_name)


def apply_datetime_heuristics_to_nested_cleaned_results(
    nested_cleaned: list[list[dict]],
    column_name: str,
) -> list[list[dict]]:
    return [
        apply_datetime_heuristics_to_cleaned_results(chunk, column_name)
        for chunk in nested_cleaned
    ]
