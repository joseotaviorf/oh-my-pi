SELECT
    action_id AS id_action,
    business_group_id AS id_business_group,
    action_type_id AS id_action_type,
    module_id AS id_module,
    action_code,
    action_type_code,
    created_by,
    last_updated_by AS updated_by,
    all_roles = 'Y' AS is_available_for_all_roles,
    is_system_action = 'Y' AS is_system_action,
    used_in_contract = 'Y' AS is_used_in_contract,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_DATE(start_date) AS dt_started,
    TO_DATE(end_date) AS dt_ended,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_pin_core_raw.per_actions_b