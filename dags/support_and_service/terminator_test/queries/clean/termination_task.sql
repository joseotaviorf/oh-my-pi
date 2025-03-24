SELECT
    id,
    termination_id AS id_termination,
    external_id AS id_external,
    origin,
    priority,
    title,
    task_manager,
    status,
    version,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_test_raw.termination_task
