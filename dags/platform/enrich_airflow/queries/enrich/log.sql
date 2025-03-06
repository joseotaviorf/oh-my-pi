SELECT
    id_log + 100000000 AS id_log, -- This is to avoid conflicts with IDs from composer
    id_dag,
    id_task,
    id_run,
    'Astro' AS source_provider,
    event,
    extra,
    owner,
    owner_display_name,
    map_index,
    try_number,
    ts_event,
    ts_executed,
    year,
    month,
    day
FROM
    datalake_astro_clean.log
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
UNION ALL
SELECT
    id_log,
    id_dag,
    id_task,
    NULL AS id_run,
    'Composer' AS source_provider,
    event,
    extra,
    owner,
    NULL AS owner_display_name,
    NULL AS map_index,
    NULL AS try_number,
    ts_event,
    ts_executed,
    year,
    month,
    day
FROM
    datalake_composer_clean.log
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
