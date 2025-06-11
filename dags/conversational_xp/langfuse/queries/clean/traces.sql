SELECT
    id AS id_trace,
    projectId AS id_project,
    sessionId AS id_session,
    userId AS id_user,
    externalId AS id_external,
    environment,
    htmlPath AS html_path,
    input,
    output,
    latency,
    name,
    observations,
    scores,
    release,
    tags,
    version,
    totalCost AS total_cost,
    bookmarked AS is_bookmarked,
    public AS is_public,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    year,
    month,
    day,
    hour
FROM
    datalake_langfuse_raw.traces
WHERE
    MAKE_TIMESTAMP(year, month, day, hour, 0, 0) >= TIMESTAMP('{load_start_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_trace ORDER BY ts_updated DESC) = 1