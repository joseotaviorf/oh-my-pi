SELECT
    policy_id AS id_policy,
    business_case_id AS id_business_case,
    policy_type,
    policy_version,
    spec,
    exploration_budget,
    is_active,
    created_at AS ts_created
FROM
    datalake_journey_optimizer_raw.business_case_policies
