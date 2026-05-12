"""I1-01: every physical Spark field documented in the lake (see ``schema_validation``)."""

from __future__ import annotations

from typing import Any, Optional

from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_i1_01_documented_physical_fields(
    i1_01_pass: Optional[Any],
    i1_01_failure_reason: Optional[Any],
) -> RequirementResult:
    """Build ``RequirementResult`` from Spark-assessment row fields (``compute_f2_02_and_i1_01_for_fqn``)."""

    if i1_01_pass is None:
        return RequirementResult("I1-01", False, "i1_01_not_assessed")
    reason: Optional[str]
    if isinstance(i1_01_failure_reason, str):
        reason = i1_01_failure_reason.strip() or None
    elif i1_01_failure_reason is not None:
        reason = str(i1_01_failure_reason).strip() or None
    else:
        reason = None
    passed = bool(i1_01_pass)
    return RequirementResult("I1-01", passed, reason=None if passed else reason)
