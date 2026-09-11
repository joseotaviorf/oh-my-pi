WITH latest_load AS (
    SELECT MAX(ts_load) AS max_ts_load
    FROM datalake_claude_usage_raw.spend_limits
),
flattened AS (
    SELECT
        GET_JSON_OBJECT(payload, '$.spend_limit_id') AS id_spend_limit,
        GET_JSON_OBJECT(payload, '$.scope.type') AS type_scope,
        GET_JSON_OBJECT(payload, '$.scope.user_id') AS id_user,
        GET_JSON_OBJECT(payload, '$.actor.type') AS type_actor,
        GET_JSON_OBJECT(payload, '$.actor.user_id') AS id_actor_user,
        GET_JSON_OBJECT(payload, '$.actor.name') AS name_actor,
        NULLIF(
            LOWER(TRIM(GET_JSON_OBJECT(payload, '$.actor.email_address'))),
            ''
        ) AS email_actor,
        CAST(GET_JSON_OBJECT(payload, '$.actor.deleted') AS BOOLEAN) AS is_actor_deleted,
        GET_JSON_OBJECT(payload, '$.source.type') AS type_source,
        GET_JSON_OBJECT(payload, '$.source.user_id') AS id_source_user,
        GET_JSON_OBJECT(payload, '$.source.rbac_group_id') AS id_source_rbac_group,
        GET_JSON_OBJECT(payload, '$.source.seat_tier') AS seat_tier,
        GET_JSON_OBJECT(payload, '$.period') AS period_type,
        GET_JSON_OBJECT(payload, '$.currency') AS currency,
        CAST(GET_JSON_OBJECT(payload, '$.amount') AS DECIMAL(18, 6)) / 100 AS sum_spend_limit_amount,
        ts_load
    FROM
        datalake_claude_usage_raw.spend_limits, latest_load
    WHERE
        ts_load = latest_load.max_ts_load
),
ranked AS (
    SELECT
        id_spend_limit,
        type_scope,
        id_user,
        type_actor,
        id_actor_user,
        name_actor,
        email_actor,
        is_actor_deleted,
        type_source,
        id_source_user,
        id_source_rbac_group,
        seat_tier,
        period_type,
        currency,
        sum_spend_limit_amount,
        ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_user,
                id_spend_limit
            ORDER BY
                ts_load DESC
        ) AS rn
    FROM
        flattened
)
SELECT
    id_spend_limit,
    id_user,
    id_actor_user,
    id_source_user,
    id_source_rbac_group,
    email_actor,
    name_actor,
    type_actor,
    type_scope,
    type_source,
    seat_tier,
    period_type,
    currency,
    sum_spend_limit_amount,
    is_actor_deleted,
    DATE(ts_load) AS dt_started,
    ts_load
FROM
    ranked
WHERE
    rn = 1
