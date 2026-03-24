SELECT
    id AS id_trace,
    project_id AS id_project,
    session_id AS id_session,
    user_id AS id_user,
    environment,
    CAST(input AS STRING) AS input,
    CAST(output AS STRING) AS output,
    name,
    release,
    tags,
    version,
    bookmarked AS is_bookmarked,
    public AS is_public,
    CAST(timestamp AS TIMESTAMP) AS ts_created,
    year,
    month,
    day,
    hour
FROM
    datalake_langfuse_raw.traces
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') - INTERVAL 1 DAY AND DATE('{load_end_date}')
    AND CAST(timestamp AS TIMESTAMP) >= TIMESTAMP('{load_start_date}') - INTERVAL 2 HOUR
    AND CAST(timestamp AS TIMESTAMP) < TIMESTAMP('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_trace ORDER BY ts_created DESC) = 1