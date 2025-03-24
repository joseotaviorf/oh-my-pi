SELECT
    id,
    termination_id AS id_termination,
    current_assignee_id AS id_current_assignee,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    current_step,
    automatically_closed AS has_automatically_closed_task,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_terminator_test_raw.termination_workflow_aud
