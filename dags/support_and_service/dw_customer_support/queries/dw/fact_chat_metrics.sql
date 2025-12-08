WITH session_metrics AS (
  SELECT 
    cm.id_sauron_session,
    DATE_DIFF(SECOND, MIN(cm.ts_created), MAX(cm.ts_created)) AS talk_time,
    ROUND(AVG(cm.reply_time), 2) AS avg_reply_time,
    COUNT(DISTINCT cm.id_message) AS messages,
    MIN(cm.ts_created) AS ts_first_message,
    MAX(cm.ts_created) AS ts_last_message
  FROM 
    datalake_chatbot.messages AS cm
  WHERE 
    cm.role IN ('HUMAN', 'ANALYST', 'AI')
  GROUP BY 1
),
conversations_type_metrics AS (
  SELECT 
    cm.id_sauron_session,
    cm.conversation_type,
    DATE_DIFF(SECOND, MIN(cm.ts_created), MAX(cm.ts_created)) AS talk_time,
    ROUND(AVG(CASE WHEN cm.role <> 'HUMAN' THEN cm.reply_time END), 2) AS avg_reply_time_message_handler,
    COUNT(DISTINCT cm.id_message) AS messages,
    COUNT(DISTINCT CASE WHEN cm.role = 'HUMAN' THEN cm.id_message END) AS human_messages,
    COUNT(DISTINCT CASE WHEN cm.role <> 'HUMAN' THEN cm.id_message END) AS messages_by_handler,
    MIN(CASE WHEN cm.role = 'HUMAN' THEN cm.ts_created END) AS ts_human_first_message,
    MIN(CASE WHEN cm.role <> 'HUMAN' THEN cm.ts_created END) AS ts_first_message_handler,
    MIN(CASE WHEN cm.role = 'HUMAN' THEN cm.reply_time END) AS human_first_reply_time,
    FIRST_VALUE(
      IF(cm.role = 'AI', cm.reply_time, NULL)
     ) IGNORE NULLS AS ai_first_reply_time,
    FIRST_VALUE(
      IF(cm.role = 'ANALYST', cm.reply_time, NULL)
     ) IGNORE NULLS AS analyst_first_reply_time,
    MIN(cm.ts_created) AS ts_first_message,
    MAX(cm.ts_created) AS ts_last_message
  FROM 
    datalake_chatbot.messages AS cm
  WHERE 
    cm.role IN ('HUMAN', 'ANALYST', 'AI')
  GROUP BY 1, 2
)
SELECT 
  sm.id_sauron_session AS sk_session,
  sm.messages as total_messages,
  sm.talk_time as total_talk_time,
  ai.talk_time AS total_talk_time_with_ai,
  ai.messages AS total_messages_with_ai,
  ai.human_messages AS total_human_messages_with_ai,
  ai.messages_by_handler AS total_ai_messages,
  ai.avg_reply_time_message_handler AS avg_reply_time_ai,
  ai.ai_first_reply_time AS first_reply_time_ai,
  CASE WHEN ai.id_sauron_session IS NOT NULL AND ai.human_first_reply_time IS NULL THEN True ELSE False END AS is_first_message_idled_with_ai,
  analyst.talk_time AS total_talk_time_with_analyst,
  analyst.messages AS total_messages_with_analyst,
  analyst.messages_by_handler AS total_analyst_messages,
  analyst.avg_reply_time_message_handler AS avg_reply_time_analyst,
  analyst.human_messages AS total_human_messages_with_analyst,
  analyst.analyst_first_reply_time AS first_reply_time_analyst,
  CASE WHEN analyst.id_sauron_session IS NOT NULL AND analyst.human_first_reply_time IS NULL THEN True ELSE False END AS is_first_message_idled_with_analyst,
  ai.ts_first_message AS ts_first_message_on_ai_handler,
  ai.ts_last_message AS ts_last_message_on_ai_handler,
  ai.ts_human_first_message AS ts_first_message_human_on_ai_handler,
  ai.ts_first_message_handler AS ts_first_message_sent_by_ai,
  analyst.ts_first_message AS ts_first_message_on_analyst_handler,
  analyst.ts_last_message AS ts_last_message_on_analyst_handler,
  analyst.ts_human_first_message AS ts_first_message_human_on_analyst_handler,
  analyst.ts_first_message_handler AS ts_first_message_sent_by_analyst,
  COALESCE(ai.ts_human_first_message, analyst.ts_human_first_message) AS ts_first_message_session_human,
  sm.ts_first_message AS ts_first_message_session,
  sm.ts_last_message AS ts_last_message_session
FROM 
  session_metrics AS sm
LEFT JOIN
  conversations_type_metrics AS ai
    ON sm.id_sauron_session = ai.id_sauron_session
      AND ai.conversation_type = 'HUMAN-AI'
LEFT JOIN 
  conversations_type_metrics AS analyst
    ON sm.id_sauron_session = analyst.id_sauron_session
      AND analyst.conversation_type = 'HUMAN-HUMAN'