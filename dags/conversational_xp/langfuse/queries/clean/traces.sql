-- Native year/month/day predicates so EMR Spark 3.5 can prune partitions.
WITH deduped AS (
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
        GET_JSON_OBJECT(CAST(metadata AS STRING), '$.feature_flags') AS feature_flags,
        bookmarked AS is_bookmarked,
        public AS is_public,
        CAST(timestamp AS TIMESTAMP) AS ts_created,
        year,
        month,
        day,
        hour,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(timestamp AS TIMESTAMP) DESC) AS rn
    FROM
        datalake_langfuse_raw.traces
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
    id_trace,
    id_project,
    id_session,
    id_user,
    environment,
    input,
    output,
    name,
    release,
    tags,
    version,
    feature_flags,
    is_bookmarked,
    is_public,
    ts_created,
    year,
    month,
    day,
    hour
FROM
    deduped
WHERE
    rn = 1
