WITH whatsapp_messages AS
(
  SELECT DISTINCT
    ce.id_channel,
    ce.id AS id_message,
    COALESCE(chat.id_session, c.id_session) AS id_sauron_session,
    REPLACE(REPLACE(REPLACE(ce.from_phone_number, 'whatsapp:', ''), '_2E', '.'), '_40', '@') AS user_sender,
    ce.message_body AS message,
    ce.ts_created,
    CASE
        WHEN from_phone_number = 'system' THEN 'Bot'
        WHEN from_phone_number LIKE '%whatsapp%' THEN 'User'
        WHEN REPLACE(REPLACE(from_phone_number,'_2E', '.'), '_40', '@')  LIKE '%@%' THEN 'Analyst'
        WHEN from_phone_number LIKE '%@%' THEN 'Analyst'
        ELSE NULL
      END AS user_type
  FROM
    datalake_quinto_messenger_clean.channel_event AS ce
  LEFT JOIN
    datalake_quinto_messenger_clean.channel AS c
      ON c.id_channel = ce.id_channel
      AND ce.ts_created < "2026-02-23T14:00:00.000+00:00"
  LEFT JOIN
    -- The addition of this source and date validation was due to a migration by the engineering team.
    -- In the future, we will no longer need the channel base as a source.
    datalake_quinto_messenger_clean.chat AS chat
      ON ce.id_channel = chat.id_channel
      AND ce.ts_created > "2026-02-23T14:00:00.000+00:00"
  WHERE
    MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
),
inapp_messages AS (
  SELECT DISTINCT
    icm.id_channel,
    icm.id_message,
    MAX(c.id_session) AS id_sauron_session,
    REPLACE(REPLACE(icm.id_user_external,'_2E', '.'), '_40', '@') AS user_sender,
    icm.message,
    icm.ts_created,
    CASE
      WHEN id_user_external = 'system' THEN 'Bot'
      WHEN REPLACE(REPLACE(id_user_external,'_2E', '.'), '_40', '@')  LIKE '%@%' THEN 'Analyst'
      WHEN id_user_external IS NOT NULL THEN 'User'
      ELSE NULL
    END AS user_type
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
    id_channel,
    id_message,
    id_sauron_session,
    user_sender,
    message,
    user_type,
    ts_created
  FROM
    whatsapp_messages
  UNION ALL
  SELECT
    id_channel,
    id_message,
    id_sauron_session,
    user_sender,
    message,
    user_type,
    ts_created
  FROM
    inapp_messages
),
messages_w_users AS (
  SELECT DISTINCT
    m.id_message,
    m.id_channel,
    m.id_sauron_session,
    CASE
      WHEN m.user_sender = 'system' THEN -1
      WHEN m.user_type = 'Analyst' THEN u1.id
      WHEN s.user_data:["user_id"] IS NOT NULL
        AND m.user_type = 'User' THEN s.user_data:["user_id"]
      WHEN u1.id IS NOT NULL THEN u1.id
      WHEN STARTSWITH(m.user_sender, '+') THEN NULL
    END AS id_user,
    s.source as origin,
    m.message,
    m.user_type,
    m.ts_created
  FROM
    messages AS m
  LEFT JOIN
    datalake_sauron_clean.session AS s
      ON s.id = m.id_sauron_session
  LEFT JOIN
    datalake_ebdb_user.user AS u1
      ON u1.email = m.user_sender
      AND CONTAINS(m.user_sender, '@')
      AND u1.country_code = 'BR'
  WHERE
    m.id_sauron_session IS NOT NULL
),
spoc_session AS (
  SELECT
    c.id_session,
    MAX(c.is_spoc_task) AS is_spoc_session
  FROM
    datalake_customer_support.chats AS c
  WHERE
    MAKE_DATE(c.year, c.month, c.day) >= '{load_start_date}'
  GROUP BY
    c.id_session
  ),
messages_w_tasks AS (
  SELECT
    mw.id_channel,
    mw.id_message,
    mw.id_sauron_session AS id_session,
    mw.id_user,
    mw.origin,
    mw.message,
    mw.user_type,
    mw.ts_created,
    CASE
      WHEN LAG(mw.ts_created) OVER(PARTITION BY mw.id_sauron_session ORDER BY mw.ts_created) IS NOT NULL
        AND LAG(mw.user_type) OVER(PARTITION BY mw.id_sauron_session ORDER BY mw.ts_created) <> mw.user_type
          THEN DATE_DIFF(SECOND, LAG(mw.ts_created) OVER (PARTITION BY mw.id_sauron_session ORDER BY mw.ts_created), mw.ts_created)
      ELSE NULL
    END AS reply_time,
    c.id_task,
    c.ts_created as ts_task_twilio_created
FROM
  messages_w_users AS mw
LEFT JOIN
  datalake_customer_support.chats AS c
    ON c.id_channel = mw.id_channel
    AND c.id_session = mw.id_sauron_session
    AND mw.ts_created >= c.ts_created
    AND mw.ts_created <= c.ts_ended
    AND MAKE_DATE(c.year, c.month, c.day) >= '{load_start_date}'
LEFT JOIN spoc_session AS ss
  ON ss.id_session = mw.id_sauron_session
WHERE
  ss.is_spoc_session = true
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY mw.id_message ORDER BY c.ts_created DESC) = 1
),
ai_without_spoc AS (
  SELECT DISTINCT
  c.id_channel,
  m.id_message,
  m.id_sauron_session AS id_session,
  COALESCE(m.id_user, c.id_user) AS id_user,
  c.origin,
  m.message,
  CASE WHEN m.role LIKE 'HUMAN' THEN 'User'
    WHEN m.role LIKE 'ANALYST' THEN 'Analyst'
    WHEN m.role LIKE 'SYSTEM' THEN 'Bot'
  ELSE m.role
  END AS user_type,
  m.conversation_type,
  m.reply_time,
  m.ts_created,
  NULL AS id_task,
  NULL AS ts_task_twilio_created
FROM
  datalake_chatbot.messages AS m
LEFT JOIN
  datalake_customer_support.chats AS c
    ON c.id_session = m.id_sauron_session
    AND MAKE_DATE(c.year, c.month, c.day) >= '{load_start_date}'
WHERE
  m.conversation_type = 'HUMAN-AI'
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY m.id_message ORDER BY c.ts_created DESC) = 1
),
human_without_spoc AS (
  SELECT
  c.id_channel,
  m.id_message,
  m.id_sauron_session AS id_session,
  COALESCE(m.id_user, c.id_user) AS id_user,
  c.origin,
  m.message,
  CASE WHEN m.role LIKE 'HUMAN' THEN 'User'
    WHEN m.role LIKE 'ANALYST' THEN 'Analyst'
    WHEN m.role LIKE 'SYSTEM' THEN 'Bot'
  ELSE m.role
  END AS user_type,
  m.conversation_type,
  m.reply_time,
  m.ts_created,
  c.id_task,
  c.ts_created as ts_task_twilio_created
FROM
  datalake_chatbot.messages AS m
LEFT JOIN
  datalake_customer_support.chats AS c
    ON c.id_session = m.id_sauron_session
    AND m.ts_created >= c.ts_created
    AND m.ts_created <= c.ts_ended
    AND MAKE_DATE(c.year, c.month, c.day) >= '{load_start_date}'
WHERE
  m.conversation_type = 'HUMAN-HUMAN'
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY m.id_message ORDER BY c.ts_created DESC) = 1
),
all_without_spoc AS (
  SELECT
    id_channel,
    id_message,
    id_session,
    id_user,
    origin,
    message,
    user_type,
    reply_time,
    ts_created,
    id_task,
    ts_task_twilio_created
  FROM
    ai_without_spoc
  UNION ALL
  SELECT
    id_channel,
    id_message,
    id_session,
    id_user,
    origin,
    message,
    user_type,
    reply_time,
    ts_created,
    id_task,
    ts_task_twilio_created
  FROM
   human_without_spoc
),
all_messages_with_tasks AS (
  SELECT
    id_channel,
    id_message,
    id_session,
    id_user,
    origin,
    message,
    user_type,
    reply_time,
    ts_created,
    id_task,
    ts_task_twilio_created
  FROM
    messages_w_tasks
  UNION ALL
  SELECT
    id_channel,
    id_message,
    id_session,
    CAST(COALESCE(id_user, -1) AS BIGINT) AS id_user,
    origin,
    message,
    user_type,
    reply_time,
    ts_created,
    id_task,
    ts_task_twilio_created
  FROM
    all_without_spoc
)
SELECT
  id_channel AS sk_channel,
  MD5(id_message) AS sk_message,
  id_task AS sk_task,
  id_session AS sk_session,
  COALESCE(id_user, -1) AS sk_user_sender,
  origin,
  user_type,
  message,
  ROW_NUMBER() OVER(PARTITION BY id_session ORDER BY ts_created) AS message_index,
  reply_time,
  ts_created,
  ts_task_twilio_created,
  NOW() AS ts_load
FROM
  all_messages_with_tasks
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY id_message ORDER BY ts_created DESC) = 1