SELECT
    constraint_id AS id_constraint,
    business_case_id AS id_business_case,
    name AS constraint_name,
    description,
    condition,
    excluded_action_codes,
    fallback_action_by_excluded_code,
    evaluation_phase,
    priority,
    is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_journey_optimizer_raw.business_case_constraints
