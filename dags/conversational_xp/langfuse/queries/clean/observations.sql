-- Native year/month/day/hour predicates so EMR Spark 3.5 can prune partitions.
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
                year DESC,
                month DESC,
                day DESC,
                hour DESC,
                CAST(end_time AS TIMESTAMP) DESC NULLS LAST
        ) AS rn
    FROM
        datalake_langfuse_raw.observations
    WHERE
        (
            (
                YEAR(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                    = YEAR(TIMESTAMP('{load_end_date}'))
                AND MONTH(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                    = MONTH(TIMESTAMP('{load_end_date}'))
                AND DAY(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                    = DAY(TIMESTAMP('{load_end_date}'))
                AND year = YEAR(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                AND month = MONTH(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                AND day = DAY(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                AND hour >= HOUR(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                AND hour <= HOUR(TIMESTAMP('{load_end_date}'))
            )
            OR
            (
                (
                    YEAR(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                        <> YEAR(TIMESTAMP('{load_end_date}'))
                    OR MONTH(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                        <> MONTH(TIMESTAMP('{load_end_date}'))
                    OR DAY(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                        <> DAY(TIMESTAMP('{load_end_date}'))
                )
                AND (
                    (
                        year = YEAR(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                        AND month = MONTH(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                        AND day = DAY(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                        AND hour >= HOUR(TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR)
                    )
                    OR
                    (
                        year = YEAR(TIMESTAMP('{load_end_date}'))
                        AND month = MONTH(TIMESTAMP('{load_end_date}'))
                        AND day = DAY(TIMESTAMP('{load_end_date}'))
                        AND hour <= HOUR(TIMESTAMP('{load_end_date}'))
                    )
                )
            )
        )
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
