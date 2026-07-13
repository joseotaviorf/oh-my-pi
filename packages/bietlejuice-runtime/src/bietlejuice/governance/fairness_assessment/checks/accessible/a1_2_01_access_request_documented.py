from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_a1_2_01_access_request_documented(
    has_how_to_request_access: bool,
) -> RequirementResult:
    """A1.2-01 (Tier 2 — how to obtain access): access request path is documented.

    Passes when the DataHub entity carries the **How to request access** structured property with a
    non-empty value (see ``DATAHUB_SP_HOW_TO_REQUEST_ACCESS_URN``). This tells a would-be consumer how
    to obtain access to the asset under policy.
    """
    return RequirementResult(
        requirement_id="A1.2-01",
        passed=has_how_to_request_access,
        reason=(
            None
            if has_how_to_request_access
            else "no_how_to_request_access_structured_property"
        ),
    )
