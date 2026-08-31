-- Native year/month/day predicates so EMR Spark 3.5 can prune partitions.
WITH ranked AS (
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
        hour,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY CAST(timestamp AS TIMESTAMP) DESC
        ) AS rn
    FROM
        datalake_langfuse_raw.scores
    WHERE
        (
            (
                year = YEAR(DATE('{load_start_date}') - INTERVAL 1 DAY)
                AND month = MONTH(DATE('{load_start_date}') - INTERVAL 1 DAY)
                AND day = DAY(DATE('{load_start_date}') - INTERVAL 1 DAY)
            )
            OR
            (
                year = YEAR(DATE('{load_start_date}'))
                AND month = MONTH(DATE('{load_start_date}'))
                AND day = DAY(DATE('{load_start_date}'))
            )
            OR
            (
                year = YEAR(DATE('{load_end_date}'))
                AND month = MONTH(DATE('{load_end_date}'))
                AND day = DAY(DATE('{load_end_date}'))
            )
        )
        AND CAST(timestamp AS TIMESTAMP) >= TIMESTAMP('{load_start_date}') - INTERVAL 2 HOUR
        AND CAST(timestamp AS TIMESTAMP) < TIMESTAMP('{load_end_date}')
)
SELECT
    id_score,
    id_trace,
    id_session,
    id_observation,
    id_project,
    metadata,
    comment,
    data_type,
    environment,
    name,
    source,
    string_value,
    value,
    ts_created,
    year,
    month,
    day,
    hour
FROM
    ranked
WHERE
    rn = 1
