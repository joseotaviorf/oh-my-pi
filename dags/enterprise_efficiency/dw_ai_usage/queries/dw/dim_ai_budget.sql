WITH history AS (
    SELECT
        'claude' AS tool,
        id_user,
        period_type,
        currency,
        sum_spend_limit_amount,
        is_actor_deleted,
        dt_started
    FROM
        datalake_claude_usage_clean.spend_limits
),
versioned AS (
    SELECT
        tool,
        id_user,
        period_type,
        currency,
        sum_spend_limit_amount,
        is_actor_deleted,
        dt_started AS dt_valid_from,
        COALESCE(
            DATE_ADD(
                LEAD(dt_started) OVER (
                    PARTITION BY
                        tool,
                        id_user,
                        period_type
                    ORDER BY
                        dt_started
                ),
                -1
            ),
            DATE('9999-12-31')
        ) AS dt_valid_to
    FROM
        history
),
resolved AS (
    SELECT
        versioned.tool,
        versioned.id_user,
        versioned.period_type,
        versioned.currency,
        versioned.sum_spend_limit_amount,
        versioned.is_actor_deleted,
        versioned.dt_valid_from,
        versioned.dt_valid_to,
        COALESCE(dau.sk_ai_user, -1) AS sk_ai_user
    FROM
        versioned
    LEFT JOIN
        dw_ai_usage.dim_ai_user AS dau
            ON dau.tool = versioned.tool
            AND dau.id_user = versioned.id_user
)
SELECT
    -- Hashed from the raw natural key (id_user), not the resolved surrogate: unknown
    -- member rows all COALESCE to the same -1 FK, which would collapse distinct
    -- unmatched rows onto one grain key if hashed post-resolution.
    MD5(
        CONCAT_WS(
            ',',
            resolved.tool,
            resolved.id_user,
            resolved.period_type,
            CAST(resolved.dt_valid_from AS STRING)
        )
    ) AS sk_ai_budget_version,
    resolved.sk_ai_user,
    resolved.tool,
    resolved.period_type,
    resolved.currency,
    resolved.sum_spend_limit_amount,
    resolved.is_actor_deleted,
    resolved.dt_valid_from,
    resolved.dt_valid_to,
    resolved.dt_valid_to = DATE('9999-12-31') AS is_current
FROM
    resolved
