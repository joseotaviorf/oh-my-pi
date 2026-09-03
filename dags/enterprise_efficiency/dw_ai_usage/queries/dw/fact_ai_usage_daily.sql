WITH usage AS (
    SELECT
        tool,
        id_user,
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
        dt_started,
        dt_ended
    FROM
        datalake_ai_usage.usage_daily
),
resolved AS (
    SELECT
        usage.tool,
        usage.id_user,
        usage.model,
        usage.product,
        usage.dt_started,
        usage.dt_ended,
        COALESCE(dau.sk_ai_user, -1) AS sk_ai_user,
        COALESCE(dam.sk_ai_model, -1) AS sk_ai_model,
        COALESCE(dap.sk_ai_product, -1) AS sk_ai_product,
        usage.is_actor_deleted,
        usage.count_requests,
        usage.count_output_tokens,
        usage.count_total_tokens,
        usage.count_uncached_input_tokens,
        usage.count_cache_read_input_tokens,
        usage.count_cache_creation_1h_tokens,
        usage.count_cache_creation_5m_tokens,
        usage.count_web_search_requests
    FROM
        usage
    LEFT JOIN
        dw_ai_usage.dim_ai_user AS dau
            ON dau.tool = usage.tool
            AND dau.id_user = usage.id_user
    LEFT JOIN
        dw_ai_usage.dim_ai_model AS dam
            ON dam.tool = usage.tool
            AND dam.model = usage.model
    LEFT JOIN
        dw_ai_usage.dim_ai_product AS dap
            ON dap.tool = usage.tool
            AND dap.product = usage.product
)
SELECT
    -- Hashed from the raw natural key (id_user/model/product), not the resolved
    -- surrogates: unknown-member rows all COALESCE to the same -1 FK, which would
    -- collapse distinct unmatched rows onto one grain key if hashed post-resolution.
    MD5(
        CONCAT_WS(
            ',',
            resolved.tool,
            CAST(resolved.dt_started AS STRING),
            CAST(resolved.dt_ended AS STRING),
            resolved.id_user,
            resolved.model,
            resolved.product
        )
    ) AS sk_ai_usage_daily,
    resolved.sk_ai_user,
    resolved.sk_ai_model,
    resolved.sk_ai_product,
    resolved.count_requests,
    resolved.count_output_tokens,
    resolved.count_total_tokens,
    resolved.count_uncached_input_tokens,
    resolved.count_cache_read_input_tokens,
    resolved.count_cache_creation_1h_tokens,
    resolved.count_cache_creation_5m_tokens,
    resolved.count_web_search_requests,
    resolved.is_actor_deleted,
    resolved.dt_started,
    resolved.dt_ended,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    resolved
