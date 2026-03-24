SELECT
    id AS id_score,
    trace_id AS id_trace,
    session_id AS id_session,
    observation_id AS id_observation,
    project_id AS id_project,
    metadata,
    comment,
    data_type,
    environment,
    name,
    source,
    string_value,
    value,
    CAST(timestamp AS TIMESTAMP) AS ts_created,
    year,
    month,
    day,
    hour
FROM
    datalake_langfuse_raw.scores
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') - INTERVAL 1 DAY AND DATE('{load_end_date}')
    AND CAST(timestamp AS TIMESTAMP) >= TIMESTAMP('{load_start_date}') - INTERVAL 2 HOUR
    AND CAST(timestamp AS TIMESTAMP) < TIMESTAMP('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_score ORDER BY ts_created DESC) = 1
