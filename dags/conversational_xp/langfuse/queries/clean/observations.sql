WITH deduped AS (
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
        latency,
        CAST(start_time AS TIMESTAMP) AS ts_started,
        CAST(end_time AS TIMESTAMP) AS ts_ended,
        year,
        month,
        day,
        hour,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY
                MAKE_TIMESTAMP(year, month, day, hour, 0, 0) DESC,
                CAST(end_time AS TIMESTAMP) DESC NULLS LAST
        ) AS rn
    FROM
        datalake_langfuse_raw.observations
    WHERE
        MAKE_TIMESTAMP(year, month, day, hour, 0, 0) >= TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR
        AND MAKE_TIMESTAMP(year, month, day, hour, 0, 0) < TIMESTAMP('{load_end_date}')
        AND CAST(start_time AS TIMESTAMP) >= TIMESTAMP('{load_start_date}') - INTERVAL 2 HOUR
        AND CAST(start_time AS TIMESTAMP) < TIMESTAMP('{load_end_date}')
)

SELECT
    id_observation,
    id_parent_observation,
    id_trace,
    id_project,
    input,
    output,
    environment,
    metadata,
    provided_model_name,
    model_parameters,
    name,
    type,
    level,
    usage_details,
    cost_details,
    latency,
    ts_started,
    ts_ended,
    year,
    month,
    day,
    hour
FROM
    deduped
WHERE
    rn = 1
