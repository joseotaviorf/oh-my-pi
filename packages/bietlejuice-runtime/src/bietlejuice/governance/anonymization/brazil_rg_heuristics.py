"""Brazil RG classification heuristics for Presidio post-processing (DPLT-967).

RG has no national validation standard; this module reduces false positives while
keeping recall for formatted and unformatted values in the lake.
"""

from __future__ import annotations

import re
from typing import Optional

BRAZIL_RG_ENTITY = "BRAZIL_RG"

PHONE_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(phone|telefone|celular|whatsapp|mobile|fone|ddd)(?:_|$)|"
    r"phone_|_phone"
)

RG_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(rg|numero_rg|rg_numero|documento_rg|nr_rg)(?:_|$)|"
    r"(?:^|_)identidade(?:_|$)"
)

RG_COLUMN_EXCLUDE_RE = re.compile(r"(?i)identidade_genero|gender_identity")

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


def is_strong_rg_column_name(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    if RG_COLUMN_EXCLUDE_RE.search(column_name):
        return False
    return bool(RG_COLUMN_RE.search(column_name))


def is_valid_cpf(digits: str) -> bool:
    if len(digits) != 11 or not digits.isdigit():
        return False
    if digits == digits[0] * 11:
        return False

    def _check_digit(base: str, weights: list[int]) -> int:
        total = sum(int(base[i]) * weights[i] for i in range(len(weights)))
        remainder = total % 11
        return 0 if remainder < 2 else 11 - remainder

    first = _check_digit(digits[:9], list(range(10, 1, -1)))
    second = _check_digit(digits[:9] + str(first), list(range(11, 1, -1)))
    return digits[-2:] == f"{first}{second}"


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
    has_column_signal = is_strong_rg_column_name(column_name)
    has_envelope = matches_rg_structural_envelope(normalized)
    has_formatted = matches_formatted_ssp_sp(matched_value)
    has_sp_dv = has_envelope and ssp_sp_check_digit_valid(normalized)

    if is_phone_like_column(column_name):
        return has_column_signal and (has_envelope or has_formatted or has_sp_dv)

    return has_column_signal or has_envelope or has_formatted or has_sp_dv


def _negative_rg_signals(column_name: str, matched_value: str) -> bool:
    normalized = normalize_rg_value(matched_value)
    if is_money_like(matched_value):
        return True
    if len(normalized) == 11 and is_valid_cpf(normalized):
        return True
    if is_brazil_mobile_like(normalized):
        return True
    if (
        len(normalized) == 11
        and normalized.isdigit()
        and not is_strong_rg_column_name(column_name)
    ):
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
    """Filter Presidio RG hits and optionally promote missed true positives."""
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

    if promote_if_missing and not kept_rg:
        for matched_value in raw_matched_values:
            if matched_value == "SAMPLE_TOO_BIG":
                continue
            if should_keep_brazil_rg(column_name, matched_value):
                adjusted.append(
                    {
                        "type": BRAZIL_RG_ENTITY,
                        "score": 0.85,
                        "matched_value": matched_value,
                    }
                )
                break

    return adjusted


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
    if not promote_if_missing:
        return adjusted

    has_rg = any(
        item.get("type") == BRAZIL_RG_ENTITY for chunk in adjusted for item in chunk
    )
    if has_rg:
        return adjusted

    for matched_value in raw_matched_values:
        if matched_value == "SAMPLE_TOO_BIG":
            continue
        if should_keep_brazil_rg(column_name, matched_value):
            adjusted.append(
                [
                    {
                        "type": BRAZIL_RG_ENTITY,
                        "score": 0.85,
                        "matched_value": matched_value,
                    }
                ]
            )
            break

    return adjusted
