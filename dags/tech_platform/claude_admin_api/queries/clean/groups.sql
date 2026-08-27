WITH flattened AS (
    SELECT
        GET_JSON_OBJECT(payload, '$.id') AS id,
        GET_JSON_OBJECT(payload, '$.name') AS name_group,
        GET_JSON_OBJECT(payload, '$.type') AS type_group,
        GET_JSON_OBJECT(payload, '$.source_type') AS type_source,
        FROM_JSON(GET_JSON_OBJECT(payload, '$.roles'), 'array<string>') AS roles,
        CAST(GET_JSON_OBJECT(payload, '$.created_at') AS TIMESTAMP) AS ts_created,
        CAST(GET_JSON_OBJECT(payload, '$.updated_at') AS TIMESTAMP) AS ts_updated,
        ts_load,
        year,
        month,
        day
    FROM
        datalake_claude_usage_raw.groups
),
ranked AS (
    SELECT
        id,
        name_group,
        type_group,
        type_source,
        roles,
        ts_created,
        ts_updated,
        ts_load,
        year,
        month,
        day,
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
    name_group,
    type_group,
    type_source,
    roles,
    ts_created,
    ts_updated,
    ts_load,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
