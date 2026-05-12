"""F2-02: substantive column descriptions vs physical Spark field names (see ``schema_validation``)."""

from __future__ import annotations

from typing import Any, Optional

from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_f2_02_substantive_column_descriptions(
    f2_02_pass: Optional[Any],
    f2_02_failure_reason: Optional[Any],
) -> RequirementResult:
    """Build ``RequirementResult`` from Spark-assessment row fields (``compute_f2_02_and_i1_01_for_fqn``)."""

    if f2_02_pass is None:
        return RequirementResult("F2-02", False, "f2_02_not_assessed")
    reason: Optional[str]
    if isinstance(f2_02_failure_reason, str):
        reason = f2_02_failure_reason.strip() or None
    elif f2_02_failure_reason is not None:
        reason = str(f2_02_failure_reason).strip() or None
    else:
        reason = None
    passed = bool(f2_02_pass)
    return RequirementResult("F2-02", passed, reason=None if passed else reason)
