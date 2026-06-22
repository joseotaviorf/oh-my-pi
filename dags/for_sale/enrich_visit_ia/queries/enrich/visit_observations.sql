WITH base AS (
    SELECT
        id_observation,
        id_trace,
        name,
        FROM_JSON(
            input,
            'STRUCT<
            visitCode: STRING,
            userRole: STRING,
            eventType: STRING,
            reason: STRING
            >'
        ) AS params,
        ts_started
    FROM
        datalake_langfuse_clean.observations
    WHERE
        DATE(ts_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND type = 'TOOL'
        AND level = 'DEFAULT'
        AND REGEXP_LIKE(name, '(?i)finish_visit')
)
SELECT
    id_observation,
    id_trace,
    name,
    params.visitCode AS visit_code,
    params.userRole AS user_role,
    params.eventType AS event_type,
    params.reason AS reason,
    ts_started,
    YEAR(ts_started) AS year,
    MONTH(ts_started) AS month,
    DAYOFMONTH(ts_started) AS day
FROM
    base
