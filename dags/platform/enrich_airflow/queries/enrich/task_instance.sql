SELECT
    ti.id_task,
    ti.id_dag,
    ti.id_run,
    ti.id_queued_by_job,
    ti.id_process,
    ti.id_trigger,
    ti.id_job,
    'Astro' AS source_provider,
    ti.task_state,
    ti.hostname,
    ti.unixname,
    ti.pool,
    ti.queue,
    ti.operator,
    ti.custom_operator_name,
    ti.executor,
    ti.task_display_name,
    ti.map_index,
    ti.try_number,
    ti.max_tries,
    ti.duration,
    ti.pool_slots,
    ti.priority_weight,
    ti.ts_trigger_timeout,
    dr.ts_executed,
    ti.ts_queued,
    ti.ts_started,
    ti.ts_ended,
    ti.ts_updated,
    ti.year,
    ti.month,
    ti.day
FROM
    datalake_astro_clean.task_instance AS ti
JOIN
    datalake_airflow.dag_run AS dr
        ON ti.id_run = dr.id_run
        AND ti.id_dag = dr.id_dag
        AND dr.source_provider = 'Astro'
WHERE
    MAKE_DATE(ti.year, ti.month, ti.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
UNION ALL
SELECT
    ti.id_task,
    ti.id_dag,
    dr.id_run,
    NULL AS id_queued_by_job,
    NULL AS id_process,
    NULL AS id_trigger,
    NULL AS id_job,
    'Composer' AS source_provider,
    ti.task_state,
    NULL AS hostname,
    NULL AS unixname,
    NULL AS pool,
    NULL AS queue,
    NULL AS operator,
    NULL AS custom_operator_name,
    NULL AS executor,
    NULL AS task_display_name,
    NULL AS map_index,
    ti.try_number,
    ti.max_tries,
    ti.duration,
    NULL AS pool_slots,
    NULL AS priority_weight,
    NULL AS ts_trigger_timeout,
    ti.ts_executed,
    NULL AS ts_queued,
    ti.ts_started,
    ti.ts_ended,
    NULL AS ts_updated,
    ti.year,
    ti.month,
    ti.day
FROM
    datalake_composer_clean.task_instance AS ti
JOIN
    datalake_composer_clean.dag_run AS dr
        ON dr.id_dag = ti.id_dag
        AND ti.ts_executed = dr.ts_executed
WHERE
    MAKE_DATE(ti.year, ti.month, ti.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
