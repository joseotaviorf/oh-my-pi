from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_f1_02_fqn_unique(fqn_occurrence_count: int) -> RequirementResult:
    ok = fqn_occurrence_count == 1
    return RequirementResult(
        requirement_id="F1-02",
        passed=ok,
        reason=None if ok else "duplicate_fqn_in_assessment_universe",
    )
