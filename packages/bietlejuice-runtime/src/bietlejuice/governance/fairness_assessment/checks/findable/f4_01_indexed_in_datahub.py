from __future__ import annotations

from typing import Optional

from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_ENTITY_NOT_FOUND,
)
from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_f4_01_indexed_in_datahub(
    f4_pass: bool,
    *,
    failure_reason: Optional[str] = None,
) -> RequirementResult:
    if f4_pass:
        return RequirementResult(requirement_id="F4-01", passed=True, reason=None)
    resolved = (failure_reason or "").strip() or DATAHUB_ENTITY_NOT_FOUND
    return RequirementResult(
        requirement_id="F4-01",
        passed=False,
        reason=resolved,
    )
