SELECT
    MD5(
        CONCAT_WS(
            ',',
            'claude',
            CAST(ua.dt_last_activity AS STRING),
            ua.id_user
        )
    ) AS sk_ai_engagement_daily,
    COALESCE(dau.sk_ai_user, -1) AS sk_ai_user,
    ua.count_chat_distinct_conversations,
    ua.count_chat_messages,
    ua.count_claude_code_commits,
    ua.count_claude_code_pull_requests,
    ua.count_claude_code_lines_added,
    ua.count_claude_code_lines_removed,
    ua.count_cowork_messages,
    ua.count_cowork_actions,
    ua.count_cowork_dispatch_turns,
    COALESCE(ua.count_chat_messages, 0)
        + COALESCE(ua.count_claude_code_commits, 0)
        + COALESCE(ua.count_cowork_messages, 0) > 0 AS is_active_day,
    ua.dt_last_activity,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_claude_usage_clean.user_activity AS ua
LEFT JOIN
    dw_ai_usage.dim_ai_user AS dau
        ON dau.tool = 'claude'
        AND dau.id_user = ua.id_user
