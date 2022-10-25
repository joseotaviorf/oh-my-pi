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
    created_at AS ts_created
FROM
    datalake_terminator_raw.termination_task
