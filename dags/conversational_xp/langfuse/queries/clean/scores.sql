SELECT
    id AS id_score,
    traceId AS id_trace,
    observationId AS id_observation,
    sessionId AS id_session,
    authorUserId AS id_author_user,
    configId AS id_config,
    queueId AS id_queue,
    projectId AS id_project,
    comment,
    dataType AS data_type,
    environment,
    name,
    source,
    stringValue AS string_value,
    trace,
    value,
    createdAt AS ts_created,
    updatedAt AS ts_updated,
    year,
    month,
    day,
    hour
FROM
    datalake_langfuse_raw.scores
WHERE
    MAKE_TIMESTAMP(year, month, day, hour, 0, 0) >= TIMESTAMP('{load_start_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_score ORDER BY ts_updated DESC) = 1