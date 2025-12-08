WITH ai_messages AS (
  SELECT DISTINCT
    s.id_sauron_session,
    m.id AS id_message,
    CASE
      WHEN m.role != 'HUMAN' THEN -1
      ELSE s.id_user
    END AS id_user,
    m.role,
    m.input_type,
    m.content AS message,
    m.processing_status,
    m.media_url,
    m.media_type,
    m.ts_created
  FROM
    datalake_copilot_service_clean.message AS m
  LEFT JOIN
    datalake_copilot_service_clean.session AS s
      ON s.id = m.id_session
  WHERE
    s.ts_created >= '{load_start_date}'
),
ai_message_count AS (
  SELECT
    id_sauron_session,
    COUNT(*) AS total_messages
  FROM
    ai_messages
  WHERE
    role != 'HARDCODED'
  GROUP BY 1
),
whatsapp_messages AS (
  SELECT DISTINCT
    ce.id AS id_message,
    c.id_session AS id_sauron_session,
    REPLACE(ce.from_phone_number, 'whatsapp:', '') AS user_sender,
    ce.message_body AS message,
    ce.ts_created,
    CASE
        WHEN from_phone_number = 'system' THEN 'SYSTEM'
        WHEN from_phone_number LIKE '%whatsapp%' THEN 'HUMAN'
        WHEN REPLACE(REPLACE(from_phone_number,'_2E', '.'), '_40', '@')  LIKE '%@%' THEN 'ANALYST'
        WHEN from_phone_number LIKE '%@%' THEN 'ANALYST'
        ELSE NULL
      END AS role
  FROM
    datalake_quinto_messenger_clean.channel_event AS ce
  LEFT JOIN
    datalake_quinto_messenger_clean.channel AS c
      ON c.id_channel = ce.id_channel
  WHERE
    MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
),
inapp_messages AS (
  SELECT DISTINCT
    icm.id_message,
    MAX(c.id_session) AS id_sauron_session,
    REPLACE(REPLACE(icm.id_user_external,'_2E', '.'), '_40', '@') AS user_sender,
    icm.message,
    icm.ts_created,
    CASE
      WHEN id_user_external = 'system' THEN 'SYSTEM'
      WHEN REPLACE(REPLACE(id_user_external,'_2E', '.'), '_40', '@')  LIKE '%@%' THEN 'ANALYST'
      WHEN id_user_external IS NOT NULL THEN 'HUMAN'
      ELSE NULL
    END AS role
  FROM
    datalake_internal_chat_clean.internal_chat_messages AS icm
  LEFT JOIN
    datalake_quinto_messenger_clean.chat AS c
      ON c.id_channel = icm.id_channel
  WHERE
    MAKE_DATE(icm.year, icm.month, icm.day) >= '{load_start_date}'
  GROUP BY ALL
),
messages AS (
  SELECT
    id_message,
    id_sauron_session,
    user_sender,
    message,
    role,
    ts_created
  FROM
    whatsapp_messages
  UNION ALL
  SELECT
    id_message,
    id_sauron_session,
    user_sender,
    message,
    role,
    ts_created
  FROM
    inapp_messages
),
messages_trimmed AS (
  SELECT
    m.*
  FROM
    messages AS m
  LEFT JOIN
    ai_message_count AS amc
      ON amc.id_sauron_session = m.id_sauron_session
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY m.id_sauron_session ORDER BY m.ts_created) > COALESCE(total_messages, 0)
),
messages_w_users AS (
  SELECT DISTINCT
    m.id_message,
    m.id_sauron_session,
    CASE
      WHEN m.user_sender = 'system' THEN -1
      WHEN STARTSWITH(m.user_sender, '+') THEN NULL
      WHEN s.user_data:["user_id"] IS NOT NULL 
        AND m.role = 'HUMAN' THEN s.user_data:["user_id"]
      WHEN u1.id IS NOT NULL THEN u1.id
    END AS id_user,
    m.message,
    m.role,
    m.ts_created
  FROM
    messages_trimmed AS m
  LEFT JOIN
    datalake_sauron_clean.session AS s
      ON s.id = m.id_sauron_session
  LEFT JOIN
    datalake_ebdb_user.user AS u1
      ON u1.email = m.user_sender
      AND CONTAINS(m.user_sender, '@')
      AND u1.country_code = 'BR'
  WHERE
    s.source_environment != 'QuintoandarSupport:OFFBOARDING'
),
all_messages AS (
  SELECT
    id_message,
    id_sauron_session,
    id_user,
    message,
    CASE
      WHEN MIN(CASE WHEN role = 'ANALYST' THEN ts_created END)
        OVER(PARTITION BY id_sauron_session) IS NULL THEN 'HUMAN-AI'
      WHEN ts_created < MIN(CASE WHEN role = 'ANALYST' THEN ts_created END)
        OVER(PARTITION BY id_sauron_session) THEN 'HUMAN-AI'
      ELSE 'HUMAN-HUMAN'
    END AS conversation_type,
    role,
    ts_created
  FROM
    messages_w_users
  UNION ALL
  SELECT 
    id_message,
    id_sauron_session,
    id_user,
    message,
    'HUMAN-AI' AS conversation_type,
    role,
    ts_created
  FROM 
    ai_messages
)
SELECT DISTINCT
  id_message,
  id_sauron_session,
  id_user,
  message,
  ROW_NUMBER() OVER(PARTITION BY id_sauron_session ORDER BY ts_created) AS message_index,
  conversation_type,
  role,
  CASE
    WHEN LAG(ts_created) OVER(PARTITION BY id_sauron_session ORDER BY ts_created) IS NOT NULL
      AND LAG(role) OVER(PARTITION BY id_sauron_session ORDER BY ts_created) <> role
        THEN DATE_DIFF(SECOND, LAG(ts_created) OVER (PARTITION BY id_sauron_session ORDER BY ts_created), ts_created)
    ELSE NULL
  END AS reply_time,
  ts_created
FROM 
  all_messages
WHERE
  id_sauron_session IS NOT NULL