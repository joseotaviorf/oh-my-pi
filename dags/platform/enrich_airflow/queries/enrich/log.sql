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
    CAST(ts_event AS STRING) AS ts_event, -- needed in order to avoid casting errors
    CAST(ts_executed AS STRING) AS ts_executed, -- needed in order to avoid casting errors
    CAST(year AS BIGINT) AS year,
    CAST(month AS BIGINT) AS month,
    CAST(day AS BIGINT) AS day
FROM
    datalake_astro_clean.log
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'