WITH ivr AS (
    SELECT
        id_task,
        id_call,
        from_phone_number,
        to_phone_number,
        STR_TO_MAP(
        REGEXP_REPLACE(REPLACE(ivr_steps, '"', ''), '^\\{{|\\}}\\}}$', ""),
            '\\}},',
            ':\\{{'
        ) AS ivr_steps_map,
        MIN(ts_created) OVER(PARTITION BY id_task) AS ts_ivr_started
    FROM
        datalake_bigfone_clean.event
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
        AND workflow_name = 'IVR Events'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_created DESC) = 1
),
exploded_ivrs AS (
    SELECT
        id_task,
        id_call,
        from_phone_number,
        to_phone_number,
        EXPLODE(ivr_steps_map) AS (step_name, step_data),
        ts_ivr_started
    FROM
        ivr
),
exploded_events AS (
    SELECT
        id_task,
        id_call,
        from_phone_number,
        to_phone_number,
        step_name,
        EXPLODE(STR_TO_MAP(step_data)) AS (kind, value),
        ts_ivr_started
    FROM
        exploded_ivrs
)
SELECT
    id_call,
    id_task,
    from_phone_number,
    to_phone_number,
    step_name,
    MAX(UPPER(value)) AS type,
    MAX(
        CASE
            WHEN kind = 'digits' THEN value
        END
    ) AS value,
    MAX(
        CASE
            WHEN kind = 'timestamp' THEN TIMESTAMP_MILLIS(CAST(value AS BIGINT))
        END
    ) AS ts_event,
    ts_ivr_started,
    YEAR(ts_ivr_started) AS year,
    MONTH(ts_ivr_started) AS month,
    DAY(ts_ivr_started) AS day
FROM
    exploded_events
GROUP BY ALL
