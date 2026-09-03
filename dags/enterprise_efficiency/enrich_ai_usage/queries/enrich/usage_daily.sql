SELECT
    'claude' AS tool,
    id_user,
    email_user,
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
    dt_starting AS dt_started,
    dt_ending AS dt_ended,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_claude_usage_clean.user_usage
