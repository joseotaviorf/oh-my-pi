SELECT
    process_task_role_id AS id_process_task_role,
    language,
    source_lang AS source_language,
    mgr_task_name AS translated_manager_task_name,
    wkr_task_name AS translated_worker_task_name,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    CAST(creation_date AS TIMESTAMP) AS ts_created,
    CAST(last_update_date AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_performance_raw.hra_pf_task_roles_tl
