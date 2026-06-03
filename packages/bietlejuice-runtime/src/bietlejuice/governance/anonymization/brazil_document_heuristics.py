"""Brazil CPF/CNPJ check-digit validation for Presidio post-processing (DPLT-968)."""

from __future__ import annotations

import re
from typing import Optional

BRAZIL_CPF_ENTITY = "BRAZIL_CPF"
BRAZIL_CNPJ_ENTITY = "BRAZIL_CNPJ"

_CPF_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(cpf|numero_cpf|cpf_numero|nr_cpf)(?:_|$)|.*cpf.*"
)
_CNPJ_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(cnpj|numero_cnpj|cnpj_numero|nr_cnpj)(?:_|$)|cnpj"
)
_DOCUMENT_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(national_document(?:_number)?|document_number|documento(?:_nacional)?|"
    r"numero_documento|nr_documento|id_documento)(?:_|$)|"
    r".*national_document.*|.*document_number.*"
)


def is_document_like_column(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    if _CPF_COLUMN_RE.search(column_name) or _CNPJ_COLUMN_RE.search(column_name):
        return True
    return bool(_DOCUMENT_COLUMN_RE.search(column_name))


_CPF_WEIGHTS_FIRST = list(range(10, 1, -1))
_CPF_WEIGHTS_SECOND = list(range(11, 1, -1))
_CNPJ_WEIGHTS_FIRST = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
_CNPJ_WEIGHTS_SECOND = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]


def normalize_document_digits(value: Optional[str]) -> str:
    if value is None:
        return ""
    return re.sub(r"\D", "", str(value).strip())


def _mod11_check_digit(base: str, weights: list[int]) -> int:
    total = sum(int(base[i]) * weights[i] for i in range(len(weights)))
    remainder = total % 11
    return 0 if remainder < 2 else 11 - remainder


def is_valid_cpf(digits: str) -> bool:
    if len(digits) != 11 or not digits.isdigit():
        return False
    if digits == digits[0] * 11:
        return False
    first = _mod11_check_digit(digits[:9], _CPF_WEIGHTS_FIRST)
    second = _mod11_check_digit(digits[:9] + str(first), _CPF_WEIGHTS_SECOND)
    return digits[-2:] == f"{first}{second}"


def is_valid_cnpj(digits: str) -> bool:
    if len(digits) != 14 or not digits.isdigit():
        return False
    if digits == digits[0] * 14:
        return False
    first = _mod11_check_digit(digits[:12], _CNPJ_WEIGHTS_FIRST)
    second = _mod11_check_digit(digits[:12] + str(first), _CNPJ_WEIGHTS_SECOND)
    return digits[-2:] == f"{first}{second}"


def should_keep_brazil_cpf(
    column_name: Optional[str], matched_value: Optional[str]
) -> bool:
    if matched_value is None:
        return False
    value = str(matched_value).strip()
    if not value or value == "SAMPLE_TOO_BIG":
        return False
    digits = normalize_document_digits(value)
    if not digits:
        return False
    return is_valid_cpf(digits)


def should_keep_brazil_cnpj(
    column_name: Optional[str], matched_value: Optional[str]
) -> bool:
    if matched_value is None:
        return False
    value = str(matched_value).strip()
    if not value or value == "SAMPLE_TOO_BIG":
        return False
    digits = normalize_document_digits(value)
    if not digits:
        return False
    return is_valid_cnpj(digits)


def _demote_entity(item: dict) -> dict:
    return {
        "type": "NOT_FOUND",
        "score": 0.0,
        "matched_value": item.get("matched_value"),
    }


def apply_brazil_document_to_cleaned_results(
    cleaned_results: list[dict],
    column_name: str,
    raw_matched_values: list,
    promote_if_missing: bool = False,
) -> list[dict]:
    """Filter CPF/CNPJ hits that fail check-digit validation."""
    adjusted = []
    kept_cpf = False
    kept_cnpj = False
    for item in cleaned_results:
        entity_type = item.get("type")
        if entity_type == BRAZIL_CPF_ENTITY:
            if should_keep_brazil_cpf(column_name, item.get("matched_value")):
                adjusted.append(item)
                kept_cpf = True
            else:
                adjusted.append(_demote_entity(item))
            continue
        if entity_type == BRAZIL_CNPJ_ENTITY:
            if should_keep_brazil_cnpj(column_name, item.get("matched_value")):
                adjusted.append(item)
                kept_cnpj = True
            else:
                adjusted.append(_demote_entity(item))
            continue
        adjusted.append(item)

    if not promote_if_missing:
        return adjusted

    for matched_value in raw_matched_values:
        if matched_value == "SAMPLE_TOO_BIG":
            continue
        if not kept_cpf and should_keep_brazil_cpf(column_name, matched_value):
            adjusted.append(
                {
                    "type": BRAZIL_CPF_ENTITY,
                    "score": 0.85,
                    "matched_value": matched_value,
                }
            )
            kept_cpf = True
        if not kept_cnpj and should_keep_brazil_cnpj(column_name, matched_value):
            adjusted.append(
                {
                    "type": BRAZIL_CNPJ_ENTITY,
                    "score": 0.85,
                    "matched_value": matched_value,
                }
            )
            kept_cnpj = True
    return adjusted


def _promote_document_in_chunk(chunk: list[dict], entity_type: str) -> None:
    """Promote the chunk's own sample value to a document entity, in place.

    Keeps the one-inner-list-per-sample contract: the matched sample is
    re-typed within its existing chunk instead of appending a new list, so
    explode/groupBy in the loader cannot inflate ``sample_summary`` counts.
    """
    matched_value = chunk[0].get("matched_value")
    promoted = {"type": entity_type, "score": 0.85, "matched_value": matched_value}
    for index, item in enumerate(chunk):
        if item.get("type") == "NOT_FOUND":
            chunk[index] = promoted
            return
    chunk.append(promoted)


def apply_brazil_document_to_nested_cleaned_results(
    nested_cleaned: list[list[dict]],
    column_name: str,
    raw_matched_values: list,
    promote_if_missing: bool = False,
) -> list[list[dict]]:
    """Apply document heuristics per sample; optionally promote missed CPF/CNPJ."""
    promote_documents = promote_if_missing or is_document_like_column(column_name)
    adjusted = [
        apply_brazil_document_to_cleaned_results(
            chunk,
            column_name,
            [chunk[0]["matched_value"]] if chunk else [],
            promote_if_missing=False,
        )
        for chunk in nested_cleaned
    ]
    if not promote_documents:
        return adjusted

    for chunk in adjusted:
        if not chunk:
            continue
        matched_value = chunk[0].get("matched_value")
        if matched_value == "SAMPLE_TOO_BIG":
            continue
        has_cpf = any(item.get("type") == BRAZIL_CPF_ENTITY for item in chunk)
        has_cnpj = any(item.get("type") == BRAZIL_CNPJ_ENTITY for item in chunk)
        if not has_cpf and should_keep_brazil_cpf(column_name, matched_value):
            _promote_document_in_chunk(chunk, BRAZIL_CPF_ENTITY)
        elif not has_cnpj and should_keep_brazil_cnpj(column_name, matched_value):
            _promote_document_in_chunk(chunk, BRAZIL_CNPJ_ENTITY)
    return adjusted
