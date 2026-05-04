from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_a1_2_03_interim_access_policy_via_contract(
    has_data_contract: bool,
) -> RequirementResult:
    """A1.2-03 (Tier 1 — access policy / roles): interim rule aligned with program timing.

    **Interim (current):** pass if and only if the asset has an **assigned data contract** on the
    Databricks DataHub entity (same boolean as ``has_data_contract`` / I1-02 — see
    ``check_i1_02_data_contract_present``). Rationale: without a contract we cannot assert access
    policy; with a contract we treat the requirement as satisfied for this phase.

    **Future:** evaluate **metadata published to DataHub** for this asset (policy / role bindings as
    modeled in the catalog), not only contract presence; replace or refine this proxy when those
    signals are available in measurement.
    """
    return RequirementResult(
        requirement_id="A1.2-03",
        passed=has_data_contract,
        reason=(
            None
            if has_data_contract
            else "a1_2_03_interim_requires_assigned_data_contract"
        ),
    )
