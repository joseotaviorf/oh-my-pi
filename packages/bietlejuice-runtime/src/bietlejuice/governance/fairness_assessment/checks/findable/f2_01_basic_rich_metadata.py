from __future__ import annotations

from typing import Optional

from bietlejuice.governance.fairness_assessment.checks.patterns import EMAIL_RE
from bietlejuice.governance.fairness_assessment.constants import (
    METADATA_DOMAIN_CI_ALLOWLIST_RE,
)
from bietlejuice.governance.fairness_assessment.models import RequirementResult


def _ownership_failure_code(
    owner_email_normalized: Optional[str],
    is_active_employee: bool,
) -> Optional[str]:
    """At most one ownership-related failure (cascade)."""
    owner = (owner_email_normalized or "").strip()
    if not owner:
        return "owner_missing"
    if not EMAIL_RE.match(owner):
        return "owner_email_invalid_format"
    if not is_active_employee:
        return "owner_not_active_employee"
    return None


def check_f2_01_basic_rich_metadata(
    owner_email_normalized: Optional[str],
    is_active_employee: bool,
    domain: Optional[str],
    table_description: Optional[str],
) -> RequirementResult:
    failure_codes: list[str] = []
    own = _ownership_failure_code(owner_email_normalized, is_active_employee)
    if own is not None:
        failure_codes.append(own)

    dom = (str(domain).strip() if domain is not None else "")
    if not dom:
        failure_codes.append("domain_missing")
    elif not METADATA_DOMAIN_CI_ALLOWLIST_RE.fullmatch(dom):
        failure_codes.append("domain_not_in_allowlist")

    desc = (str(table_description).strip() if table_description is not None else "")
    if not desc:
        failure_codes.append("table_description_missing")

    if not failure_codes:
        return RequirementResult(
            requirement_id="F2-01",
            passed=True,
            reason=None,
            detail=None,
        )
    joined = ",".join(failure_codes)
    return RequirementResult(
        requirement_id="F2-01",
        passed=False,
        reason=joined,
        detail={"failure_codes": list(failure_codes)},
    )
