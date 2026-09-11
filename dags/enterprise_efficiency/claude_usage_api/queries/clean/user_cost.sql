WITH flattened AS (
    SELECT
        GET_JSON_OBJECT(payload, '$.actor.user_id') AS id_user,
        NULLIF(
            LOWER(TRIM(GET_JSON_OBJECT(payload, '$.actor.email'))),
            ''
        ) AS email_user,
        GET_JSON_OBJECT(payload, '$.actor.name') AS name_user,
        GET_JSON_OBJECT(payload, '$.actor.type') AS type_actor,
        GET_JSON_OBJECT(payload, '$.currency') AS currency,
        CAST(GET_JSON_OBJECT(payload, '$.requests') AS BIGINT) AS count_requests,
        CAST(GET_JSON_OBJECT(payload, '$.amount') AS DECIMAL(18, 6)) / 100 AS sum_discounted_cost_amount,
        CAST(GET_JSON_OBJECT(payload, '$.list_amount') AS DECIMAL(18, 6)) / 100 AS sum_list_price_amount,
        CAST(GET_JSON_OBJECT(payload, '$.actor.deleted') AS BOOLEAN) AS is_actor_deleted,
        CAST(GET_JSON_OBJECT(payload, '$.starting_at') AS DATE) AS dt_starting,
        CAST(GET_JSON_OBJECT(payload, '$.ending_at') AS DATE) AS dt_ending,
        ts_load,
        year,
        month,
        day
    FROM
        datalake_claude_usage_raw.user_cost
),
ranked AS (
    SELECT
        id_user,
        email_user,
        name_user,
        type_actor,
        currency,
        count_requests,
        sum_discounted_cost_amount,
        sum_list_price_amount,
        is_actor_deleted,
        dt_starting,
        dt_ending,
        ts_load,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                dt_starting,
                dt_ending,
                id_user,
                currency
            ORDER BY
                ts_load DESC
        ) AS rn
    FROM
        flattened
)
SELECT
    id_user,
    email_user,
    name_user,
    type_actor,
    currency,
    count_requests,
    sum_discounted_cost_amount,
    sum_list_price_amount,
    is_actor_deleted,
    dt_starting,
    dt_ending,
    ts_load,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
