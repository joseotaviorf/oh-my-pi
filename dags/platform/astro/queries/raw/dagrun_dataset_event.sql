SELECT
    dde.dag_run_id,
    dde.event_id
FROM
    dagrun_dataset_event AS dde
JOIN
    dag_run AS dr
        ON dr.id = dde.dag_run_id
WHERE
    dr.queued_at >= DATE('{load_start_date}')
    AND dr.queued_at <= (DATE('{load_end_date}') + 1)
