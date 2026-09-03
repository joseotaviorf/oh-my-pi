SELECT
    'claude' AS tool,
    id_user,
    email_user,
    currency,
    sum_discounted_cost_amount,
    sum_list_price_amount,
    is_actor_deleted,
    dt_starting AS dt_started,
    dt_ending AS dt_ended,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_claude_usage_clean.user_cost
