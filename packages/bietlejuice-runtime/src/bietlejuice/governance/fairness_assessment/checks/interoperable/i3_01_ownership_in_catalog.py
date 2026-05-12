from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_i3_01_ownership_in_catalog(has_ownership: bool) -> RequirementResult:
    """I3-01: at least one owner on the dataset entity in DataHub (GraphQL ``ownership``)."""

    return RequirementResult(
        requirement_id="I3-01",
        passed=has_ownership,
        reason=None if has_ownership else "ownership_empty_in_datahub",
    )
