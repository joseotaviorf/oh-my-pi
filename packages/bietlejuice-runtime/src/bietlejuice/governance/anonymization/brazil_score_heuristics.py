"""Per-entity score floors for noisy Presidio types (DPLT-970)."""

from __future__ import annotations

from typing import Optional

# Stricter bar for NER-heavy types; CPF/CNPJ rely on check-digit pass (DPLT-968).
ENTITY_MIN_SCORE = {
    "PERSON": 0.85,
    "LOCATION": 0.85,
    "PHONE_NUMBER": 0.85,
}

_NOISY_ENTITIES = frozenset(ENTITY_MIN_SCORE)


def should_keep_by_entity_score(
    entity_type: Optional[str], score: Optional[float]
) -> bool:
    if entity_type not in _NOISY_ENTITIES:
        return True
    if score is None:
        return False
    return float(score) >= ENTITY_MIN_SCORE[entity_type]


def apply_entity_score_floors_to_cleaned_results(
    cleaned_results: list[dict],
) -> list[dict]:
    adjusted = []
    for item in cleaned_results:
        entity_type = item.get("type")
        if entity_type in ("NOT_FOUND", "SAMPLE_TOO_BIG"):
            adjusted.append(item)
            continue
        if should_keep_by_entity_score(entity_type, item.get("score")):
            adjusted.append(item)
        else:
            adjusted.append(
                {
                    "type": "NOT_FOUND",
                    "score": 0.0,
                    "matched_value": item.get("matched_value"),
                }
            )
    return adjusted


def apply_entity_score_floors_to_nested_cleaned_results(
    nested_cleaned: list[list[dict]],
) -> list[list[dict]]:
    return [
        apply_entity_score_floors_to_cleaned_results(chunk) for chunk in nested_cleaned
    ]
