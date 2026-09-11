WITH flattened AS (
    SELECT
        GET_JSON_OBJECT(payload, '$.actor.user_id') AS id_user,
        NULLIF(
            LOWER(TRIM(GET_JSON_OBJECT(payload, '$.actor.email'))),
            ''
        ) AS email_user,
        GET_JSON_OBJECT(payload, '$.actor.name') AS name_user,
        GET_JSON_OBJECT(payload, '$.actor.type') AS type_actor,
        GET_JSON_OBJECT(payload, '$.model') AS model,
        GET_JSON_OBJECT(payload, '$.product') AS product,
        CAST(GET_JSON_OBJECT(payload, '$.requests') AS BIGINT) AS count_requests,
        CAST(GET_JSON_OBJECT(payload, '$.output_tokens') AS BIGINT) AS count_output_tokens,
        CAST(GET_JSON_OBJECT(payload, '$.total_tokens') AS BIGINT) AS count_total_tokens,
        CAST(GET_JSON_OBJECT(payload, '$.uncached_input_tokens') AS BIGINT) AS count_uncached_input_tokens,
        CAST(GET_JSON_OBJECT(payload, '$.cache_read_input_tokens') AS BIGINT) AS count_cache_read_input_tokens,
        CAST(GET_JSON_OBJECT(payload, '$.cache_creation.ephemeral_1h_input_tokens') AS BIGINT) AS count_cache_creation_1h_tokens,
        CAST(GET_JSON_OBJECT(payload, '$.cache_creation.ephemeral_5m_input_tokens') AS BIGINT) AS count_cache_creation_5m_tokens,
        CAST(GET_JSON_OBJECT(payload, '$.server_tool_use.web_search_requests') AS BIGINT) AS count_web_search_requests,
        CAST(GET_JSON_OBJECT(payload, '$.actor.deleted') AS BOOLEAN) AS is_actor_deleted,
        CAST(GET_JSON_OBJECT(payload, '$.starting_at') AS DATE) AS dt_starting,
        CAST(GET_JSON_OBJECT(payload, '$.ending_at') AS DATE) AS dt_ending,
        ts_load,
        year,
        month,
        day
    FROM
        datalake_claude_usage_raw.user_usage
),
ranked AS (
    SELECT
        id_user,
        email_user,
        name_user,
        type_actor,
        model,
        product,
        count_requests,
        count_output_tokens,
        count_total_tokens,
        count_uncached_input_tokens,
        count_cache_read_input_tokens,
        count_cache_creation_1h_tokens,
        count_cache_creation_5m_tokens,
        count_web_search_requests,
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
                model,
                product
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
    model,
    product,
    count_requests,
    count_output_tokens,
    count_total_tokens,
    count_uncached_input_tokens,
    count_cache_read_input_tokens,
    count_cache_creation_1h_tokens,
    count_cache_creation_5m_tokens,
    count_web_search_requests,
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
