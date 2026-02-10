SELECT
    id_log + 100000000 AS id_log, -- historically offset to avoid conflicts with Composer IDs
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