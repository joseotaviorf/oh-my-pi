SELECT
    process_task_role_id AS id_process_task_role,
    business_group_id AS id_business_group,
    process_flow_id AS id_process_flow,
    task_code,
    created_by,
    last_updated_by AS updated_by,
    CAST(sequence_number AS INT) AS sequence_number,
    CAST(object_version_number AS INT) AS object_version_number,
    CAST(creation_date AS TIMESTAMP) AS ts_created,
    CAST(last_update_date AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_pf_task_roles_b
