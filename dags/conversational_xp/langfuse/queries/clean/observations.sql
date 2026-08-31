-- Native year/month/day/hour predicates so EMR Spark 3.5 can prune partitions.
-- First/last hour-start match MAKE_TIMESTAMP(y,m,d,h,0,0) >= load_start-3h AND < load_end.
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
                YEAR(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                    = YEAR(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                AND MONTH(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                    = MONTH(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                AND DAY(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                    = DAY(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                AND year = YEAR(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                AND month = MONTH(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                AND day = DAY(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                AND hour >= HOUR(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                AND hour <= HOUR(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
            )
            OR
            (
                (
                    YEAR(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                        <> YEAR(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                    OR MONTH(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                        <> MONTH(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                    OR DAY(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                        <> DAY(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                )
                AND (
                    (
                        year = YEAR(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                        AND month = MONTH(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                        AND day = DAY(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                        AND hour >= HOUR(DATE_TRUNC('HOUR', TIMESTAMP('{load_start_date}') - INTERVAL 3 HOUR + INTERVAL 1 HOUR - INTERVAL 1 SECOND))
                    )
                    OR
                    (
                        year = YEAR(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                        AND month = MONTH(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                        AND day = DAY(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
                        AND hour <= HOUR(DATE_TRUNC('HOUR', TIMESTAMP('{load_end_date}') - INTERVAL 1 SECOND))
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
