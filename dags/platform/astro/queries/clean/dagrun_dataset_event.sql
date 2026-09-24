SELECT
    dag_run_id AS id_run,
    event_id AS id_event,
    year,
    month,
    day
FROM
    datalake_astro_raw.dagrun_dataset_event
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
