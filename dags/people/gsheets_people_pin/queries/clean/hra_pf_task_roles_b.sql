SELECT
    process_task_role_id AS id_process_task_role,
    business_group_id AS id_business_group,
    process_flow_id AS id_process_flow,
    module_id AS id_module,
    task_code AS task_code,
    created_by,
    last_updated_by AS updated_by,
    sequence_number AS sequence_num,
    object_version_number AS version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hra_pf_task_roles_b
