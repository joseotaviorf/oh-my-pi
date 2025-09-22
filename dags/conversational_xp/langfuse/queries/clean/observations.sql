SELECT
    id AS id_observation,
    parent_observation_id AS id_parent_observation,
    trace_id AS id_trace,
    project_id AS id_project,
    CAST(input AS STRING) AS input,
    CAST(output AS STRING) AS output,
    environment,
    metadata,
    provided_model_name,
    model_parameters,
    name,
    type,
    level,
    usage_details,
    cost_details,
    CAST(start_time AS TIMESTAMP) AS ts_started,
    CAST(end_time AS TIMESTAMP) AS ts_ended,
    year,
    month,
    day,
    hour
FROM
    datalake_langfuse_raw.observations
WHERE
    MAKE_TIMESTAMP(year, month, day, hour, 0, 0) >= TIMESTAMP('{load_start_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_observation ORDER BY ts_started DESC) = 1