from __future__ import annotations

from typing import Optional

from bietlejuice.governance.fairness_assessment.checks.patterns import EMAIL_RE
from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_f2_01_basic_rich_metadata(
    owner_email_normalized: Optional[str],
    is_active_employee: bool,
    domain: Optional[str],
    table_description: Optional[str],
) -> RequirementResult:
    owner = (owner_email_normalized or "").strip()
    if not owner:
        return RequirementResult(
            requirement_id="F2-01",
            passed=False,
            reason="owner_missing",
        )
    if not EMAIL_RE.match(owner):
        return RequirementResult(
            requirement_id="F2-01",
            passed=False,
            reason="owner_email_invalid_format",
        )
    if not is_active_employee:
        return RequirementResult(
            requirement_id="F2-01",
            passed=False,
            reason="owner_not_active_employee",
        )
    dom_ok = domain is not None and str(domain).strip() != ""
    desc_ok = table_description is not None and str(table_description).strip() != ""
    if not dom_ok:
        return RequirementResult(
            requirement_id="F2-01",
            passed=False,
            reason="domain_missing",
        )
    if not desc_ok:
        return RequirementResult(
            requirement_id="F2-01",
            passed=False,
            reason="table_description_missing",
        )
    return RequirementResult(requirement_id="F2-01", passed=True, reason=None)
