WITH latest_load AS (
    SELECT
        MAX(ts_load) AS max_ts_load
    FROM
        datalake_claude_usage_raw.members
),

flattened AS (
    SELECT
        GET_JSON_OBJECT(payload, '$.id') AS id,
    NULLIF(
        LOWER(TRIM(GET_JSON_OBJECT(payload, '$.email'))),
        ''
    ) AS email,
        GET_JSON_OBJECT(payload, '$.name') AS name,
        GET_JSON_OBJECT(payload, '$.role') AS role,
        GET_JSON_OBJECT(payload, '$.type') AS type_member,
        CAST(GET_JSON_OBJECT(payload, '$.added_at') AS TIMESTAMP) AS ts_added,
        ts_load
    FROM
        datalake_claude_usage_raw.members,
        latest_load
    WHERE
        ts_load = latest_load.max_ts_load
),

ranked AS (
    SELECT
        id,
        email,
        name,
        role,
        type_member,
        ts_added,
        ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY
                id
            ORDER BY
                ts_load DESC
        ) AS rn
    FROM
        flattened
)

SELECT
    id,
    email,
    name,
    role,
    type_member,
    ts_added,
    ts_load
FROM
    ranked
WHERE
    rn = 1
