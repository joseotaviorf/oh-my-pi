WITH current_load AS (
    SELECT
        GET_JSON_OBJECT(payload, '$.id') AS id_user,
        NULLIF(
            LOWER(TRIM(GET_JSON_OBJECT(payload, '$.email'))),
            ''
        ) AS email_user,
        GET_JSON_OBJECT(payload, '$.name') AS name_user,
        GET_JSON_OBJECT(payload, '$.role') AS role,
        CAST(GET_JSON_OBJECT(payload, '$.isRemoved') AS BOOLEAN) AS is_removed,
        DATE(ts_load) AS dt_snapshot,
        ts_load,
        year,
        month,
        day
    FROM
        datalake_cursor_usage_raw.members
    WHERE
        year = YEAR(DATE('{load_start_date}'))
        AND month = MONTH(DATE('{load_start_date}'))
        AND day = DAY(DATE('{load_start_date}'))
),
ranked AS (
    SELECT
        id_user,
        email_user,
        name_user,
        role,
        is_removed,
        dt_snapshot,
        ts_load,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_user,
                dt_snapshot
            ORDER BY
                ts_load DESC
        ) AS rn
    FROM
        current_load
)
SELECT
    id_user,
    email_user,
    name_user,
    role,
    is_removed,
    dt_snapshot,
    ts_load,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
