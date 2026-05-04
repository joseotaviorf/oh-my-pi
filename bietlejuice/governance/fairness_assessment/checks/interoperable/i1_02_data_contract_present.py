from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_i1_02_data_contract_present(has_data_contract: bool) -> RequirementResult:
    return RequirementResult(
        requirement_id="I1-02",
        passed=has_data_contract,
        reason=(
            None
            if has_data_contract
            else "no_assigned_data_contract_urn_in_databricks_entity"
        ),
    )
