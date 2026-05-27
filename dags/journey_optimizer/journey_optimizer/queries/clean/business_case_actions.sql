SELECT
    action_registry_id AS id_action_registry,
    business_case_id AS id_business_case,
    code,
    display_name,
    description,
    action_type,
    agent_name,
    instructions,
    aggregation_key_template,
    aggregation_strategy,
    is_aggregatable,
    aggregation_window_seconds,
    display_order,
    is_default,
    is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_journey_optimizer_raw.business_case_actions
