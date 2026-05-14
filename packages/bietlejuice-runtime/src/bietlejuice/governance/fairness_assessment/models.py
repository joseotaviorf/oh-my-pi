"""Small DTOs for FAIRness checks: requirements, tiering, and description quality."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional


@dataclass(frozen=True)
class RequirementResult:
    """Binary outcome for a single FAIR requirement ID."""

    requirement_id: str
    passed: bool
    reason: Optional[str] = None
    detail: Optional[dict[str, Any]] = None


@dataclass(frozen=True)
class TierComputationResult:
    """Outcome of tiering for one asset."""

    tier_achieved: int
    tier_max_possible: int
    mode: str


@dataclass(frozen=True)
class TableDescriptionQualityResult:
    """Outcome of :func:`~bietlejuice.governance.fairness_assessment.description_quality.assess_table_description_quality` or column-level assessment."""

    is_substantive: bool
    content_word_count: int
    non_identifier_word_count: int
    name_overlap_ratio: float
    reason_code: Optional[str] = None
