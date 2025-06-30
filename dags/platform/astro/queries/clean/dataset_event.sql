SELECT
    id,
    dataset_id AS id_dataset,
    source_dag_id AS id_source_dag,
    source_task_id AS id_source_task,
    source_run_id AS id_source_run,
    source_map_index,
    extra,
    `timestamp`::TIMESTAMP AS ts_event_created,
    year,
    month,
    day
FROM
    datalake_astro_raw.dataset_event
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
