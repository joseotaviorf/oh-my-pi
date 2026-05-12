from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_i3_02_lineage_in_catalog(has_lineage: bool) -> RequirementResult:
    """I3-02: upstream or downstream lineage total > 0 in the catalog."""

    return RequirementResult(
        requirement_id="I3-02",
        passed=has_lineage,
        reason=None if has_lineage else "no_upstream_or_downstream_lineage_in_catalog",
    )
