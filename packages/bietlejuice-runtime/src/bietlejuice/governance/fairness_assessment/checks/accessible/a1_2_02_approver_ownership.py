from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_a1_2_02_approver_ownership(
    has_approver_owner: bool,
) -> RequirementResult:
    """A1.2-02 (Tier 2 — access authorization): an access approver is identified.

    Passes when the DataHub entity has at least one owner assigned with the **Approvers** ownership
    type (see ``DATAHUB_OWNERSHIP_TYPE_APPROVERS_URN``), i.e. a person/group who can authorize access
    requests for the asset.
    """
    return RequirementResult(
        requirement_id="A1.2-02",
        passed=has_approver_owner,
        reason=(None if has_approver_owner else "no_approver_owner_in_datahub"),
    )
