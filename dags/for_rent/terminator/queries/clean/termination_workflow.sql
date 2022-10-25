SELECT
    id,
    termination_id AS id_termination,
    current_assignee_id AS id_current_assignee,
    current_step,
    automatically_closed AS has_automatically_closed_task,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_raw.termination_workflow