"""ID sets and functions for the fairness tiering model (MVP and full)."""

from __future__ import annotations

from typing import Final, FrozenSet, Mapping, Optional

from bietlejuice.governance.fairness_assessment.constants import (
    MVP_TIER2_SCOPED_REQUIREMENT_IDS,
    TIER1_ACTIVE_REQUIREMENT_IDS,
    TIER_1_IDS,
    TIER_2_EXTRA,
    TIER_3_EXTRA,
    TIER_4_EXTRA,
)
from bietlejuice.governance.fairness_assessment.models import (
    RequirementResult,
    TierComputationResult,
)

TIER_ACHIEVED_TO_CLASSIFICATION: Final[Mapping[int, str]] = {
    0: "Not FAIR",
    1: "FAIR Tier 1",
    2: "FAIR Tier 2",
    3: "FAIR Tier 3",
    4: "FAIR Tier 4",
}

# De/para for legacy verbose ``classification`` labels written before the tier-label rollout.
# The ``fairness_classification`` table is upserted (merge on FQN), so rows produced by older runs
# keep the old label until reprocessed. The DataHub push normalizes any persisted label to the
# current structured-property allowed value via :func:`normalize_classification_to_sp_value`.
_LEGACY_CLASSIFICATION_TO_SP_VALUE: Final[Mapping[str, str]] = {
    "Not FAIR": "Not FAIR",
    "Findable, Accessible": "FAIR Tier 1",
    "Findable, Accessible, Interoperable": "FAIR Tier 2",
    "Findable, Accessible, Interoperable and Reusable": "FAIR Tier 3",
    "FAIR Masterpiece": "FAIR Tier 4",
}

# Current tier labels (pass through unchanged); equal to the DataHub SP allowed values.
_CLASSIFICATION_ALLOWED_VALUES: Final[FrozenSet[str]] = frozenset(
    TIER_ACHIEVED_TO_CLASSIFICATION.values()
)


def tier_achieved_to_classification(tier_achieved: int) -> str:
    """Map persisted ``tier_achieved`` (0..4) to the product classification label."""
    if tier_achieved not in TIER_ACHIEVED_TO_CLASSIFICATION:
        raise ValueError(f"Unknown tier_achieved {tier_achieved!r}; expected 0..4")
    return TIER_ACHIEVED_TO_CLASSIFICATION[tier_achieved]


def normalize_classification_to_sp_value(
    classification: Optional[str],
) -> Optional[str]:
    """Normalize a persisted ``classification`` label to a DataHub SP allowed value.

    Accepts both current tier labels (``FAIR Tier N`` / ``Not FAIR``, returned unchanged) and the
    legacy verbose labels (mapped via :data:`_LEGACY_CLASSIFICATION_TO_SP_VALUE`). Returns ``None``
    for blank or unknown values so callers can log-and-skip rather than send an invalid value that
    the structured-property mutation would reject.
    """

    if classification is None:
        return None
    label = classification.strip()
    if not label:
        return None
    if label in _CLASSIFICATION_ALLOWED_VALUES:
        return label
    return _LEGACY_CLASSIFICATION_TO_SP_VALUE.get(label)


def cumulative_ids_for_tier(tier: int) -> FrozenSet[str]:
    """Union of all requirement IDs required for tiers 1..tier (inclusive)."""

    if tier < 1:
        return frozenset()
    acc = set(TIER_1_IDS)
    if tier >= 2:
        acc |= TIER_2_EXTRA
    if tier >= 3:
        acc |= TIER_3_EXTRA
    if tier >= 4:
        acc |= TIER_4_EXTRA
    return frozenset(acc)


def compute_tier(
    results: Mapping[str, RequirementResult],
    *,
    mode: str = "mvp",
) -> TierComputationResult:
    if mode == "mvp":
        return compute_tier_mvp(results)
    if mode == "full":
        return _compute_tier_full(results)
    raise ValueError(f"Unknown mode: {mode!r}")


def compute_tier_mvp(results: Mapping[str, RequirementResult]) -> TierComputationResult:
    """MVP: Tier 1 = all TIER1_ACTIVE checks; Tier 2 = Tier 1 + F2-02 + I1-01."""

    t1 = TIER1_ACTIVE_REQUIREMENT_IDS
    gate = MVP_TIER2_SCOPED_REQUIREMENT_IDS
    if t1 - results.keys() or not gate.issubset(frozenset(results.keys())):
        return TierComputationResult(
            tier_achieved=0,
            tier_max_possible=0,
            mode="mvp",
        )
    t1_all = all(results[rid].passed for rid in t1)
    t2_all = t1_all and all(bool(results[rid].passed) for rid in gate)
    if t2_all:
        return TierComputationResult(
            tier_achieved=2,
            tier_max_possible=2,
            mode="mvp",
        )
    if t1_all:
        return TierComputationResult(
            tier_achieved=1,
            tier_max_possible=2,
            mode="mvp",
        )
    return TierComputationResult(
        tier_achieved=0,
        tier_max_possible=2,
        mode="mvp",
    )


def _compute_tier_full(
    results: Mapping[str, RequirementResult],
) -> TierComputationResult:
    implemented = frozenset(results.keys())

    tier_max_possible = 0
    for t in range(1, 5):
        needed = cumulative_ids_for_tier(t)
        if needed <= implemented:
            tier_max_possible = t
        else:
            break

    tier_achieved = 0
    for t in range(tier_max_possible, 0, -1):
        needed = cumulative_ids_for_tier(t)
        if not needed <= implemented:
            continue
        if all(results[rid].passed for rid in needed):
            tier_achieved = t
            break

    return TierComputationResult(
        tier_achieved=tier_achieved,
        tier_max_possible=tier_max_possible,
        mode="full",
    )
