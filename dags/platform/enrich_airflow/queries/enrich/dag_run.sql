WITH astro_dag_runs AS (
    SELECT *
    FROM
        datalake_astro_clean.dag_run
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
-- We can remove this CTE when we migrate to Astro definitively
composer_dag_runs AS (
    SELECT *
    FROM
        datalake_composer_clean.dag_run
    WHERE
        DATE(GREATEST(ts_started, ts_ended)) BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT
    id + 1000000 AS id, -- This is to avoid conflict with Composer IDs
    id_dag,
    id_run,
    id_log_template,
    id_creating_job,
    'Astro' AS source_provider,
    state,
    run_type,
    configuration,
    dag_hash,
    clear_number,
    had_external_trigger,
    ts_last_scheduling_decision,
    ts_data_interval_started,
    ts_data_interval_ended,
    ts_updated,
    ts_executed,
    ts_queued,
    ts_started,
    ts_ended
FROM
    astro_dag_runs
UNION ALL
SELECT
    id,
    id_dag,
    id_run,
    NULL AS id_log_template,
    NULL AS id_creating_job,
    'Composer' AS source_provider,
    state,
    NULL AS run_type,
    configuration,
    NULL AS dag_hash,
    NULL AS clear_number,
    had_external_trigger,
    NULL AS ts_last_scheduling_decision,
    NULL AS ts_data_interval_started,
    NULL AS ts_data_interval_ended,
    NULL AS ts_updated,
    ts_executed,
    NULL AS ts_queued,
    ts_started,
    ts_ended
FROM
    composer_dag_runs
