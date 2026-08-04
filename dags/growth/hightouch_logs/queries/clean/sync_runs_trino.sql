WITH ranked AS (
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
        s.day AS day,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(s.sync_id AS STRING), CAST(s.sync_run_id AS STRING), CAST(s.model_id AS STRING)
            ORDER BY MAKE_DATE(s.year, s.month, s.day) DESC, CAST(s.started_at AS TIMESTAMP) DESC
        ) AS rn
    FROM
        datalake_hightouch_logs_raw.sync_runs_trino AS s
    WHERE
        MAKE_DATE(s.year, s.month, s.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
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
FROM
    ranked
WHERE
    rn = 1
