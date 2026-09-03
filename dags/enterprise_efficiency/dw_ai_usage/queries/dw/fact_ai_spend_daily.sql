WITH spend AS (
    SELECT
        tool,
        id_user,
        currency,
        sum_discounted_cost_amount,
        sum_list_price_amount,
        is_actor_deleted,
        dt_started,
        dt_ended
    FROM
        datalake_ai_usage.spend_daily
),
resolved AS (
    SELECT
        spend.tool,
        spend.id_user,
        spend.dt_started,
        spend.dt_ended,
        COALESCE(dau.sk_ai_user, -1) AS sk_ai_user,
        spend.currency,
        spend.is_actor_deleted,
        spend.sum_discounted_cost_amount,
        spend.sum_list_price_amount
    FROM
        spend
    LEFT JOIN
        dw_ai_usage.dim_ai_user AS dau
            ON dau.tool = spend.tool
            AND dau.id_user = spend.id_user
)
SELECT
    -- Hashed from the raw natural key (id_user), not the resolved surrogate: unknown
    -- member rows all COALESCE to the same -1 FK, which would collapse distinct
    -- unmatched rows onto one grain key if hashed post-resolution.
    MD5(
        CONCAT_WS(
            ',',
            resolved.tool,
            CAST(resolved.dt_started AS STRING),
            CAST(resolved.dt_ended AS STRING),
            resolved.id_user,
            resolved.currency
        )
    ) AS sk_ai_spend_daily,
    resolved.sk_ai_user,
    resolved.currency,
    resolved.sum_discounted_cost_amount,
    resolved.sum_list_price_amount,
    resolved.is_actor_deleted,
    resolved.dt_started,
    resolved.dt_ended,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    resolved
