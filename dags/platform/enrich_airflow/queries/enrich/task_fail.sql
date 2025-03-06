WITH astro_task_fails AS (
    SELECT tf.*, dr.ts_executed
    FROM
        datalake_astro_clean.task_fail AS tf
    JOIN
        datalake_airflow.dag_run AS dr
            ON tf.id_run = dr.id_run
            AND tf.id_dag = dr.id_dag
            AND dr.source_provider = 'Astro'
    WHERE
        MAKE_DATE(tf.year, tf.month, tf.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
composer_task_fails AS (
    SELECT tf.*, dr.id_run
    FROM
        datalake_composer_clean.task_fail AS tf
    JOIN
        datalake_composer_clean.dag_run AS dr
            ON dr.id_dag = tf.id_dag
            AND tf.ts_executed = dr.ts_executed
    WHERE
        DATE(GREATEST(tf.ts_started, tf.ts_ended)) BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT
    id_fail + 1000000 AS id_fail, -- This is to avoid conflicts with IDs from composer
    id_dag,
    id_task,
    id_run,
    'Astro' AS source_provider,
    map_index,
    duration,
    ts_ended,
    ts_started,
    ts_executed
FROM
    astro_task_fails
UNION ALL
SELECT
    id_fail,
    id_dag,
    id_task,
    id_run,
    'Composer' AS source_provider,
    NULL AS map_index,
    duration,
    ts_ended,
    ts_started,
    ts_executed
FROM
    composer_task_fails