SELECT
    'claude' AS tool,
    id_user,
    period,
    currency,
    sum_spend_limit_amount,
    sum_period_to_date_spend,
    is_actor_deleted,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_claude_usage_clean.spend_limits
