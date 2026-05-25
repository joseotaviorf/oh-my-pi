SELECT
    CAST(s.sync_id AS STRING) AS id_sync,
    CAST(s.sync_run_id AS STRING) AS id_sync_run,
    CAST(s.model_id AS STRING) AS id_model,
    CAST(s.primary_key AS STRING) AS primary_key,
    CAST(s.destination AS STRING) AS destination,
    CAST(s.model_name AS STRING) AS model_name,
    CAST(s.error AS STRING) AS error,
    CAST(s.status AS STRING) AS status,
    CAST(s.num_planned_add AS DOUBLE) AS num_planned_add,
    CAST(s.num_planned_change AS DOUBLE) AS num_planned_change,
    CAST(s.num_planned_remove AS DOUBLE) AS num_planned_remove,
    CAST(s.num_attempted_add AS DOUBLE) AS num_attempted_add,
    CAST(s.num_attempted_change AS DOUBLE) AS num_attempted_change,
    CAST(s.num_attempted_remove AS DOUBLE) AS num_attempted_remove,
    CAST(s.num_succeeded_add AS DOUBLE) AS num_succeeded_add,
    CAST(s.num_succeeded_change AS DOUBLE) AS num_succeeded_change,
    CAST(s.num_succeeded_remove AS DOUBLE) AS num_succeeded_remove,
    CAST(s.num_failed_add AS DOUBLE) AS num_failed_add,
    CAST(s.num_failed_change AS DOUBLE) AS num_failed_change,
    CAST(s.num_failed_remove AS DOUBLE) AS num_failed_remove,
    CAST(s.started_at AS TIMESTAMP) AS ts_started,
    CAST(s.finished_at AS TIMESTAMP) AS ts_finished,
    s.year AS year,
    s.month AS month,
    s.day AS day
FROM
    datalake_hightouch_logs_raw.sync_runs_trino AS s
WHERE
    MAKE_DATE(s.year, s.month, s.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY CAST(s.sync_id AS STRING), CAST(s.sync_run_id AS STRING), CAST(s.model_id AS STRING)
        ORDER BY MAKE_DATE(s.year, s.month, s.day) DESC, CAST(s.started_at AS TIMESTAMP) DESC
    ) = 1
