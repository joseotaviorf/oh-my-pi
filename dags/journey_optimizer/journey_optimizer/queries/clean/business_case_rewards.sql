SELECT
    reward_registry_id AS id_reward_registry,
    business_case_id AS id_business_case,
    trigger_binding_id AS id_trigger_binding,
    reward_type,
    value_expression,
    description,
    is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_journey_optimizer_raw.business_case_rewards
