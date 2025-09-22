SELECT
    id AS id_score,
    trace_id AS id_trace,
    observation_id AS id_observation,
    project_id AS id_project,
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
    MAKE_TIMESTAMP(year, month, day, hour, 0, 0) >= TIMESTAMP('{load_start_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_score ORDER BY ts_created DESC) = 1
