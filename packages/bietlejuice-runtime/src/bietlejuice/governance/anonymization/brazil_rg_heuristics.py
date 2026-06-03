"""Brazil RG classification heuristics for Presidio post-processing (DPLT-967).

RG has no national validation standard. This module filters weak Presidio hits and
only promotes missed RGs on columns that semantically expect a document (rg_* or
document_like). Generic numeric envelopes are never promoted.
"""

from __future__ import annotations

import re
from typing import Optional

from bietlejuice.governance.anonymization.brazil_document_heuristics import (
    is_document_like_column,
    is_valid_cpf,
)

BRAZIL_RG_ENTITY = "BRAZIL_RG"
PROMOTED_RG_SCORE = 0.85

PHONE_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(phone|telefone|celular|whatsapp|mobile|fone|ddd)(?:_|$)|"
    r"phone_|_phone"
)

EMAIL_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(email|e_mail|mail|correio|e-mail)(?:_|$)|"
    r"email_|_email|_mail$"
)

RG_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(rg|numero_rg|rg_numero|documento_rg|nr_rg)(?:_|$)|"
    r"(?:^|_)identidade(?:_|$)"
)

RG_COLUMN_EXCLUDE_RE = re.compile(r"(?i)identidade_genero|gender_identity")

IPV4_VALUE_RE = re.compile(r"^\s*\d{1,3}(?:\.\d{1,3}){3}\s*$")

DATE_VALUE_RE = re.compile(
    r"(?i)^\s*(?:"
    r"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}"
    r"|\d{1,2}[-/.]\d{1,2}[-/.]\d{4}"
    r")(?:[ t]\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:z|[+-]\d{2}:?\d{2})?)?\s*$"
)

FORMATTED_RG_SP_RE = re.compile(
    r"(?i)(?:^|[^\d])(\d{1,2}[\.\s]?\d{3}[\.\s]?\d{3}[-\s]?[\dXx])(?:[^\d]|$)"
)

MONEY_LIKE_RE = re.compile(
    r"^\s*\d{1,3}(?:[.,]\d{3})+[.,]\d{2}\s*$|^\s*\d+[.,]\d{2}\s*$"
)

_SSP_SP_WEIGHTS = (9, 8, 7, 6, 5, 4, 3, 2)


def normalize_rg_value(value: Optional[str]) -> str:
    if value is None:
        return ""
    stripped = str(value).strip()
    if not stripped:
        return ""
    return re.sub(r"[^0-9Xx]", "", stripped).upper()


def is_phone_like_column(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    return bool(PHONE_COLUMN_RE.search(column_name))


def is_email_like_column(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    return bool(EMAIL_COLUMN_RE.search(column_name))


def is_strong_rg_column_name(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    if RG_COLUMN_EXCLUDE_RE.search(column_name):
        return False
    return bool(RG_COLUMN_RE.search(column_name))


def can_promote_rg(column_name: Optional[str]) -> bool:
    """RG may only be injected on columns that semantically expect a document."""
    if not column_name:
        return False
    return is_strong_rg_column_name(column_name) or is_document_like_column(column_name)


def looks_like_ipv4(value: Optional[str]) -> bool:
    if value is None:
        return False
    return bool(IPV4_VALUE_RE.match(str(value)))


def looks_like_date_value(value: Optional[str]) -> bool:
    if value is None:
        return False
    return bool(DATE_VALUE_RE.match(str(value)))


def looks_like_email_value(value: Optional[str]) -> bool:
    if value is None:
        return False
    return "@" in str(value)


def is_brazil_mobile_like(normalized: str) -> bool:
    if len(normalized) != 11 or not normalized.isdigit():
        return False
    ddd = int(normalized[:2])
    if ddd < 11 or ddd > 99:
        return False
    return normalized[2] == "9"


def is_money_like(value: str) -> bool:
    return bool(MONEY_LIKE_RE.match(value.strip()))


def matches_formatted_ssp_sp(value: str) -> bool:
    if looks_like_email_value(value):
        return False
    if not re.search(r"[\.\s\-]", value):
        return False
    return bool(FORMATTED_RG_SP_RE.search(value))


def matches_rg_structural_envelope(normalized: str) -> bool:
    if not normalized or len(normalized) < 7 or len(normalized) > 11:
        return False
    if not re.fullmatch(r"[0-9X]+", normalized):
        return False
    digit_count = sum(character.isdigit() for character in normalized)
    return digit_count >= len(normalized) - 1


def ssp_sp_check_digit_valid(normalized: str) -> bool:
    if len(normalized) != 9:
        return False
    body = normalized[:8]
    if not body.isdigit():
        return False
    check_char = normalized[8]
    total = sum(int(body[index]) * _SSP_SP_WEIGHTS[index] for index in range(8))
    expected = total % 11
    if expected == 10:
        return check_char == "X"
    return check_char == str(expected)


def _positive_rg_signals(column_name: str, matched_value: str) -> bool:
    normalized = normalize_rg_value(matched_value)
    has_strong_column = is_strong_rg_column_name(column_name)
    has_document_column = is_document_like_column(column_name)
    has_formatted = matches_formatted_ssp_sp(matched_value)
    has_sp_dv = matches_rg_structural_envelope(normalized) and ssp_sp_check_digit_valid(
        normalized
    )
    has_envelope = matches_rg_structural_envelope(normalized)

    if has_formatted or has_sp_dv:
        return has_strong_column or has_document_column
    if has_strong_column and has_envelope:
        return True
    if has_document_column and has_envelope:
        return True
    return False


def _negative_rg_signals(column_name: str, matched_value: str) -> bool:
    normalized = normalize_rg_value(matched_value)
    if is_email_like_column(column_name):
        return True
    if is_money_like(matched_value):
        return True
    if looks_like_email_value(matched_value):
        return True
    if looks_like_date_value(matched_value):
        return True
    if len(normalized) == 11 and is_valid_cpf(normalized):
        return True
    if is_brazil_mobile_like(normalized):
        return True
    if (
        len(normalized) == 11
        and normalized.isdigit()
        and not is_strong_rg_column_name(column_name)
        and not is_document_like_column(column_name)
    ):
        return True
    if not is_strong_rg_column_name(column_name) and looks_like_ipv4(matched_value):
        return True
    return False


def should_keep_brazil_rg(
    column_name: Optional[str], matched_value: Optional[str]
) -> bool:
    if matched_value is None:
        return False
    column = column_name or ""
    if RG_COLUMN_EXCLUDE_RE.search(column):
        return False
    value = str(matched_value).strip()
    if not value or value == "SAMPLE_TOO_BIG":
        return False
    if _negative_rg_signals(column, value):
        return False
    return _positive_rg_signals(column, value)


def apply_brazil_rg_to_cleaned_results(
    cleaned_results: list[dict],
    column_name: str,
    raw_matched_values: list,
    promote_if_missing: bool = True,
) -> list[dict]:
    """Filter Presidio RG hits; optionally promote on document/rg columns only."""
    adjusted = []
    kept_rg = False
    for item in cleaned_results:
        if item.get("type") != BRAZIL_RG_ENTITY:
            adjusted.append(item)
            continue
        if should_keep_brazil_rg(column_name, item.get("matched_value")):
            adjusted.append(item)
            kept_rg = True
        else:
            adjusted.append(
                {
                    "type": "NOT_FOUND",
                    "score": 0.0,
                    "matched_value": item.get("matched_value"),
                }
            )

    if promote_if_missing and not kept_rg and can_promote_rg(column_name):
        for matched_value in raw_matched_values:
            if matched_value == "SAMPLE_TOO_BIG":
                continue
            if should_keep_brazil_rg(column_name, matched_value):
                _promote_rg_in_chunk(adjusted, matched_value)
                break

    return adjusted


def _promote_rg_in_chunk(chunk: list[dict], matched_value: str) -> None:
    """Re-type NOT_FOUND to BRAZIL_RG in place for this sample's chunk."""
    promoted = {
        "type": BRAZIL_RG_ENTITY,
        "score": PROMOTED_RG_SCORE,
        "matched_value": matched_value,
    }
    for index, item in enumerate(chunk):
        if item.get("type") == "NOT_FOUND":
            chunk[index] = promoted
            return
    chunk.append(promoted)


def apply_brazil_rg_to_nested_cleaned_results(
    nested_cleaned: list[list[dict]],
    column_name: str,
    raw_matched_values: list,
    promote_if_missing: bool = True,
) -> list[list[dict]]:
    """Apply RG heuristics per sample value (Presidio returns one list[dict] per value)."""
    adjusted = [
        apply_brazil_rg_to_cleaned_results(
            chunk,
            column_name,
            [chunk[0]["matched_value"]] if chunk else [],
            promote_if_missing=False,
        )
        for chunk in nested_cleaned
    ]
    if not promote_if_missing or not can_promote_rg(column_name):
        return adjusted

    # Promote per sample: each chunk is evaluated independently so one sample
    # that already has RG does not block promotion on other valid samples.
    for chunk in adjusted:
        if not chunk:
            continue
        matched_value = chunk[0].get("matched_value")
        if matched_value == "SAMPLE_TOO_BIG":
            continue
        if any(item.get("type") == BRAZIL_RG_ENTITY for item in chunk):
            continue
        if should_keep_brazil_rg(column_name, matched_value):
            _promote_rg_in_chunk(chunk, matched_value)

    return adjusted
