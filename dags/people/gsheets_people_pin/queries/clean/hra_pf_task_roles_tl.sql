SELECT
    process_task_role_id AS id_process_task_role,
    business_group AS business_group_name,
    language AS language_code,
    source_lang AS source_language,
    mgr_task_name AS manager_task_name,
    wkr_task_name AS worker_task_name,
    created_by,
    last_updated_by AS updated_by,
    object_version_number AS version_number,
    creation_date AS dt_created,
    last_update_date AS dt_updated,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.hra_pf_task_roles_tl
