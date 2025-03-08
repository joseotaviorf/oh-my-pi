SELECT
    id,
    dttm,
    dag_id,
    task_id,
    map_index,
    event,
    execution_date,
    run_id,
    owner,
    owner_display_name,
    extra,
    try_number
FROM
    log
WHERE
    dttm >= DATE('{load_start_date}')
    AND dttm <= (DATE('{load_end_date}') + 1)
