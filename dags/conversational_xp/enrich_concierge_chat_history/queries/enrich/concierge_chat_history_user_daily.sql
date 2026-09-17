SELECT
    chat_session.id_user,
    COUNT(DISTINCT CASE
        WHEN DATE(chat_message.ts_created) >= DATE_SUB(CURRENT_DATE(), {days_lookback_7})
        THEN chat_message.id
    END) AS qty_chat_messages_7d,
    COUNT(DISTINCT CASE
        WHEN DATE(chat_message.ts_created) >= DATE_SUB(CURRENT_DATE(), {days_lookback_28})
        THEN chat_message.id
    END) AS qty_chat_messages_28d,
    MAX(chat_message.ts_created) AS ts_last_chat_message,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    datalake_copilot_service_clean.message AS chat_message
INNER JOIN
    datalake_copilot_service_clean.session AS chat_session
    ON chat_message.id_session = chat_session.id
WHERE
    chat_session.id_user IS NOT NULL
    AND UPPER(chat_message.channel) = 'WHATSAPP_CONCIERGE_CHAT'
    AND UPPER(chat_message.role) IN ('HUMAN', 'USER')
    AND DATE(chat_message.ts_created) >= DATE_SUB(CURRENT_DATE(), {days_lookback_28})
GROUP BY
    chat_session.id_user
