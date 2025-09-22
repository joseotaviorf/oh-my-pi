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
    MAKE_TIMESTAMP(year, month, day, hour, 0, 0) >= TIMESTAMP('{load_start_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_trace ORDER BY ts_created DESC) = 1