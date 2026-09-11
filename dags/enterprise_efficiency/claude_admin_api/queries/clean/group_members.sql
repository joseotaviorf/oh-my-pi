WITH latest_load AS (
    SELECT
        MAX(ts_load) AS max_ts_load
    FROM
        datalake_claude_usage_raw.group_members
),

flattened AS (
    SELECT
        GET_JSON_OBJECT(payload, '$.group_id') AS id_group,
        GET_JSON_OBJECT(payload, '$.user_id') AS id_user,
        GET_JSON_OBJECT(payload, '$.email') AS email,
        GET_JSON_OBJECT(payload, '$.type') AS type_group_member,
        CAST(GET_JSON_OBJECT(payload, '$.created_at') AS TIMESTAMP) AS ts_created,
        ts_load
    FROM
        datalake_claude_usage_raw.group_members,
        latest_load
    WHERE
        ts_load = latest_load.max_ts_load
),

ranked AS (
    SELECT
        id_group,
        id_user,
        email,
        type_group_member,
        ts_created,
        ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_group,
                id_user
            ORDER BY
                ts_load DESC
        ) AS rn
    FROM
        flattened
)

SELECT
    id_group,
    id_user,
    NULLIF(LOWER(TRIM(email)), '') AS email,
    type_group_member,
    ts_created,
    ts_load
FROM
    ranked
WHERE
    rn = 1
