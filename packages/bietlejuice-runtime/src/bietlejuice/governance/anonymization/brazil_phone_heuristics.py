"""Brazil phone classification heuristics for Presidio post-processing (DPLT-970).

DPLT-970 raised the PHONE_NUMBER score floor to 0.85, which drops weak column-name
hits. Combined with DATE_TIME demotion on phone columns, real phone columns such as
``mobile_phone`` and ``consorcio_phone_number_formatted`` ended up as NOT_FOUND.

This module keeps PHONE_NUMBER hits whose value is a Brazilian phone, and promotes
PHONE_NUMBER on phone-like columns when a sample value looks like a phone.
"""

from __future__ import annotations

import re
from typing import Optional

from bietlejuice.governance.anonymization.brazil_document_heuristics import (
    is_valid_cpf,
)
from bietlejuice.governance.anonymization.brazil_rg_heuristics import (
    is_money_like,
    is_phone_like_column,
)

PHONE_NUMBER_ENTITY = "PHONE_NUMBER"

_LANDLINE_FIRST_DIGITS = frozenset("2345")


def _phone_digits(value: Optional[str]) -> str:
    if value is None:
        return ""
    return re.sub(r"\D", "", str(value).strip())


def _normalize_national(digits: str) -> str:
    """Strip the +55 country code when present, returning national-format digits."""
    if len(digits) in (12, 13) and digits.startswith("55"):
        return digits[2:]
    return digits


def looks_like_brazil_phone(value: Optional[str]) -> bool:
    """True for 10-digit landline or 11-digit mobile (optionally +55 prefixed)."""
    if value is None:
        return False
    raw = str(value).strip()
    if not raw or raw == "SAMPLE_TOO_BIG":
        return False
    if is_money_like(raw):
        return False
    digits = _normalize_national(_phone_digits(raw))
    if len(digits) not in (10, 11):
        return False
    if digits == digits[0] * len(digits):
        return False
    ddd = int(digits[:2])
    if ddd < 11 or ddd > 99:
        return False
    if len(digits) == 11:
        # CPF check-digit collisions: an 11-digit valid CPF is not a phone.
        if is_valid_cpf(digits):
            return False
        return digits[2] == "9"
    return digits[2] in _LANDLINE_FIRST_DIGITS


def should_keep_phone(column_name: Optional[str], matched_value: Optional[str]) -> bool:
    if looks_like_brazil_phone(matched_value):
        return True
    return False


def _promote_phone_in_chunk(chunk: list[dict], matched_value: str) -> None:
    """Re-type an existing NOT_FOUND entry to PHONE_NUMBER instead of appending.

    After score floors or demotion, the chunk may already contain NOT_FOUND for
    this sample; appending a promoted PHONE_NUMBER would duplicate entities and
    inflate ``sample_summary`` counts on explode/groupBy.
    """
    promoted = {
        "type": PHONE_NUMBER_ENTITY,
        "score": 0.85,
        "matched_value": matched_value,
    }
    for index, item in enumerate(chunk):
        if item.get("type") == "NOT_FOUND":
            chunk[index] = promoted
            return
    chunk.append(promoted)


def apply_phone_to_cleaned_results(
    cleaned_results: list[dict],
    column_name: str,
    raw_matched_values: list,
    promote_if_missing: bool = True,
) -> list[dict]:
    """Filter Presidio PHONE_NUMBER hits and promote missed phones on phone columns."""
    adjusted = []
    kept_phone = False
    for item in cleaned_results:
        if item.get("type") != PHONE_NUMBER_ENTITY:
            adjusted.append(item)
            continue
        if should_keep_phone(column_name, item.get("matched_value")):
            adjusted.append(item)
            kept_phone = True
        else:
            adjusted.append(
                {
                    "type": "NOT_FOUND",
                    "score": 0.0,
                    "matched_value": item.get("matched_value"),
                }
            )

    if promote_if_missing and not kept_phone and is_phone_like_column(column_name):
        for matched_value in raw_matched_values:
            if matched_value == "SAMPLE_TOO_BIG":
                continue
            if looks_like_brazil_phone(matched_value):
                _promote_phone_in_chunk(adjusted, matched_value)
                break

    return adjusted


def apply_phone_to_nested_cleaned_results(
    nested_cleaned: list[list[dict]],
    column_name: str,
    raw_matched_values: list,
    promote_if_missing: bool = True,
) -> list[list[dict]]:
    """Apply phone heuristics per sample value (one list[dict] per value)."""
    return [
        apply_phone_to_cleaned_results(
            chunk,
            column_name,
            [chunk[0]["matched_value"]] if chunk else [],
            promote_if_missing=promote_if_missing,
        )
        for chunk in nested_cleaned
    ]
