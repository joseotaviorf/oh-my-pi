SELECT
    id_sync,
    id_sync_run,
     id_model,
    primary_key,
    destination,
    model_name,
    error,
    status,

    num_planned_add,
    num_planned_change,
    num_planned_remove,
    num_attempted_add,
    num_attempted_change,
    num_attempted_remove,
    num_succeeded_add,
    num_succeeded_change,
    num_succeeded_remove,
    num_failed_add,
    num_failed_change,
    num_failed_remove,

    ts_started,
    ts_finished,
    year,
    month,
    day
FROM datalake_hightouch_logs_clean.sync_runs_databricks
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION ALL

SELECT
    id_sync,
    id_sync_run,
    id_model,
    primary_key,
    destination,
    model_name,
    error,
    status,

    num_planned_add,
    num_planned_change,
    num_planned_remove,
    num_attempted_add,
    num_attempted_change,
    num_attempted_remove,
    num_succeeded_add,
    num_succeeded_change,
    num_succeeded_remove,
    num_failed_add,
    num_failed_change,
    num_failed_remove,

    ts_started,
    ts_finished,
    year,
    month,
    day

FROM datalake_hightouch_logs_clean.sync_runs_trino
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
