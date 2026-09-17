-- a channel maps to many sessions over time; pick the one whose active window
-- contains the message timestamp so each id_message resolves to a single session
-- and the fan-out across all of a channel's sessions no longer duplicates messages
WITH whatsapp_channel_session AS (
  SELECT
    id_message,
    id_session
  FROM (
    SELECT
      ce.id AS id_message,
      c.id_session,
      ROW_NUMBER() OVER (
        PARTITION BY ce.id
        ORDER BY
          CASE
            WHEN ce.ts_created BETWEEN c.ts_created AND c.ts_updated THEN 0
            ELSE 1
          END,
          c.ts_created DESC
      ) AS session_rank
    FROM
      datalake_quinto_messenger_clean.channel_event AS ce
    INNER JOIN
      -- The addition of this source and date validation was due to a migration by the engineering team.
      -- In the future, we will no longer need the channel base as a source.
      datalake_quinto_messenger_clean.channel AS c
        ON c.id_channel = ce.id_channel
        AND ce.ts_created < "2026-02-23T14:00:00.000+00:00"
    WHERE
      MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
  ) AS ranked_channel
  WHERE
    session_rank = 1
),
whatsapp_sauron_session AS (
  SELECT
    id_message,
    id_session
  FROM (
    SELECT
      ce.id AS id_message,
      chat.id_session,
      ROW_NUMBER() OVER (
        PARTITION BY ce.id
        ORDER BY
          CASE
            WHEN ce.ts_created BETWEEN chat.ts_created AND chat.ts_updated THEN 0
            ELSE 1
          END,
          chat.ts_created DESC
      ) AS session_rank
    FROM
      datalake_quinto_messenger_clean.channel_event AS ce
    INNER JOIN
      datalake_quinto_messenger_clean.chat AS chat
        ON chat.id_channel = ce.id_channel
        AND ce.ts_created > "2026-02-23T14:00:00.000+00:00"
        AND chat.source = 'sauron'
    WHERE
      MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
  ) AS ranked_sauron_chat
  WHERE
    session_rank = 1
),
whatsapp_sss_session AS (
  SELECT
    id_message,
    id_session
  FROM (
    SELECT
      ce.id AS id_message,
      chat2.id_session,
      ROW_NUMBER() OVER (
        PARTITION BY ce.id
        ORDER BY
          CASE
            WHEN ce.ts_created BETWEEN chat2.ts_created AND chat2.ts_updated THEN 0
            ELSE 1
          END,
          chat2.ts_created DESC
      ) AS session_rank
    FROM
      datalake_quinto_messenger_clean.channel_event AS ce
    INNER JOIN
      datalake_quinto_messenger_clean.chat AS chat2
        ON chat2.id_channel = ce.id_channel
        AND ce.ts_created > "2026-02-23T14:00:00.000+00:00"
        AND chat2.source = 'support_session'
    WHERE
      MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
  ) AS ranked_sss_chat
  WHERE
    session_rank = 1
),
whatsapp_messages AS
(
  SELECT DISTINCT
    ce.id_channel,
    ce.id AS id_message,
    COALESCE(wsauron.id_session, wchannel.id_session) AS id_sauron_session,
    wsss.id_session AS id_sss_session,
    REPLACE(REPLACE(REPLACE(ce.from_phone_number, 'whatsapp:', ''), '_2E', '.'), '_40', '@') AS user_sender,
    ce.message_body AS message,
    ce.ts_created,
    CASE
        WHEN ce.from_phone_number = 'system' THEN 'Bot'
        WHEN ce.from_phone_number LIKE '%whatsapp%' THEN 'User'
        WHEN REPLACE(REPLACE(ce.from_phone_number,'_2E', '.'), '_40', '@')  LIKE '%@%' THEN 'Analyst'
        WHEN ce.from_phone_number LIKE '%@%' THEN 'Analyst'
        ELSE NULL
      END AS user_type
  FROM
    datalake_quinto_messenger_clean.channel_event AS ce
  LEFT JOIN
    whatsapp_channel_session AS wchannel
      ON wchannel.id_message = ce.id
  LEFT JOIN
    whatsapp_sauron_session AS wsauron
      ON wsauron.id_message = ce.id
  LEFT JOIN
    whatsapp_sss_session AS wsss
      ON wsss.id_message = ce.id
  WHERE
    MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
),
inapp_messages AS (
  SELECT DISTINCT
    icm.id_channel,
    icm.id_message,
    MAX(c.id_session) AS id_sauron_session,
    MAX(css.id_session) AS id_sss_session,
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
      AND c.source = 'sauron'
    LEFT JOIN
    datalake_quinto_messenger_clean.chat AS css
      ON css.id_channel = icm.id_channel
      AND css.source = 'support_session'
  WHERE
    MAKE_DATE(icm.year, icm.month, icm.day) >= '{load_start_date}'
  GROUP BY
    icm.id_channel,
    icm.id_message,
    REPLACE(REPLACE(icm.id_user_external,'_2E', '.'), '_40', '@'),
    icm.message,
    icm.ts_created,
    CASE
      WHEN id_user_external = 'system' THEN 'Bot'
      WHEN REPLACE(REPLACE(id_user_external,'_2E', '.'), '_40', '@')  LIKE '%@%' THEN 'Analyst'
      WHEN id_user_external IS NOT NULL THEN 'User'
      ELSE NULL
    END
),
messages AS (
  SELECT
    id_channel,
    id_message,
    id_sauron_session,
    id_sss_session,
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
    id_sss_session,
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
    m.id_sss_session,
    CASE
      WHEN m.user_sender = 'system' THEN -1
      WHEN m.user_type = 'Analyst' THEN u1.id
      WHEN m.user_type = 'User' THEN COALESCE(
        GET_JSON_OBJECT(s_num.user_data, '$.user_id'),
        GET_JSON_OBJECT(s_hash.user_data, '$.user_id'),
        GET_JSON_OBJECT(ss.user_data, '$.user_id'),
        NULLIF(REGEXP_EXTRACT(s_num.user_data, 'user_id["'']?\\s*:\\s*["'']?([^,"''}}\\s]+)', 1), ''),
        NULLIF(REGEXP_EXTRACT(s_hash.user_data, 'user_id["'']?\\s*:\\s*["'']?([^,"''}}\\s]+)', 1), ''),
        NULLIF(REGEXP_EXTRACT(ss.user_data, 'user_id["'']?\\s*:\\s*["'']?([^,"''}}\\s]+)', 1), '')
      )
      WHEN u1.id IS NOT NULL THEN u1.id
      WHEN STARTSWITH(m.user_sender, '+') THEN NULL
    END AS id_user,
    COALESCE(s_num.source, s_hash.source, ss.source) AS origin,
    m.message,
    m.user_type,
    m.ts_created
  FROM
    messages AS m
  LEFT JOIN
    datalake_sauron_clean.session AS s_num
      ON s_num.id = TRY_CAST(m.id_sauron_session AS BIGINT)
  LEFT JOIN
    datalake_sauron_clean.session AS s_hash
      ON s_hash.public_id = m.id_sauron_session
  LEFT JOIN
    datalake_support_session_service_clean.support_session AS ss
      ON ss.public_id = m.id_sss_session
  LEFT JOIN
    datalake_ebdb_user.user AS u1
      ON u1.email = m.user_sender
      AND CONTAINS(m.user_sender, '@')
      AND u1.country_code = 'BR'
  WHERE
COALESCE(m.id_sauron_session, m.id_sss_session) IS NOT NULL
),
spoc_session AS (
  SELECT
    c.id_session,
    c.id_sss_session,
    MAX(c.is_spoc_task) AS is_spoc_session
  FROM
    datalake_customer_support.chats AS c
  WHERE
    MAKE_DATE(c.year, c.month, c.day) >= '{load_start_date}'
  GROUP BY
    c.id_session,
    c.id_sss_session
),
-- UNION of equi-joins reproduces the old OR filter: a message matching both
-- keys still yields one id_message; two distinct SPOC rows each matching one
-- key still yield that one message (downstream ROW_NUMBER is per id_message)
spoc_message_ids AS (
  SELECT
    mw.id_message
  FROM
    messages_w_users AS mw
  INNER JOIN
    spoc_session AS ss
      ON ss.id_session = mw.id_sauron_session
  WHERE
    ss.is_spoc_session = true
  UNION
  SELECT
    mw.id_message
  FROM
    messages_w_users AS mw
  INNER JOIN
    spoc_session AS ss
      ON ss.id_sss_session = mw.id_sss_session
  WHERE
    ss.is_spoc_session = true
),
messages_w_tasks_ranked AS (
SELECT
    mw.id_channel,
    mw.id_message,
    mw.id_sauron_session AS id_session,
    mw.id_sss_session,
    CASE
      WHEN mw.user_type = 'Analyst' THEN mw.id_user
      WHEN mw.user_type = 'Bot' THEN COALESCE(mw.id_user, -1)
      ELSE COALESCE(mw.id_user, c_cast.id_user, c_hash.id_user, sss.id_user)
    END AS id_user,
    mw.origin,
    mw.message,
    mw.user_type,
    mw.ts_created,
    CASE
      WHEN LAG(mw.ts_created) OVER(PARTITION BY COALESCE(mw.id_sauron_session, mw.id_sss_session) ORDER BY mw.ts_created) IS NOT NULL
        AND LAG(mw.user_type) OVER(PARTITION BY COALESCE(mw.id_sauron_session, mw.id_sss_session) ORDER BY mw.ts_created) <> mw.user_type
          THEN TIMESTAMPDIFF(SECOND, LAG(mw.ts_created) OVER (PARTITION BY COALESCE(mw.id_sauron_session, mw.id_sss_session) ORDER BY mw.ts_created), mw.ts_created)
      ELSE NULL
    END AS reply_time,
    COALESCE(c_cast.id_task, c_hash.id_task, sss.id_task) AS id_task,
    COALESCE(c_cast.ts_created, c_hash.ts_created, sss.ts_created) AS ts_task_twilio_created,
    ROW_NUMBER() OVER (PARTITION BY mw.id_message ORDER BY COALESCE(c_cast.ts_created, c_hash.ts_created, sss.ts_created) DESC) AS rn
FROM
  messages_w_users AS mw
LEFT JOIN
  datalake_customer_support.chats AS c_cast
    ON c_cast.id_channel = mw.id_channel
    AND c_cast.id_session = TRY_CAST(mw.id_sauron_session AS BIGINT)
    AND mw.ts_created >= c_cast.ts_created
    AND mw.ts_created <= c_cast.ts_ended
    AND MAKE_DATE(c_cast.year, c_cast.month, c_cast.day) >= '{load_start_date}'
LEFT JOIN
  datalake_customer_support.chats AS c_hash
    ON c_hash.id_channel = mw.id_channel
    AND c_hash.id_sss_session = mw.id_sauron_session
    AND mw.ts_created >= c_hash.ts_created
    AND mw.ts_created <= c_hash.ts_ended
    AND MAKE_DATE(c_hash.year, c_hash.month, c_hash.day) >= '{load_start_date}'
LEFT JOIN
  datalake_customer_support.chats AS sss
    ON sss.id_channel = mw.id_channel
    AND sss.id_sss_session = mw.id_sss_session
    AND mw.ts_created >= sss.ts_created
    AND mw.ts_created <= sss.ts_ended
    AND MAKE_DATE(sss.year, sss.month, sss.day) >= '{load_start_date}'
INNER JOIN
  spoc_message_ids AS sm
    ON sm.id_message = mw.id_message
),
messages_w_tasks AS (
  SELECT
    id_channel,
    id_message,
    id_session,
    id_sss_session,
    id_user,
    origin,
    message,
    user_type,
    ts_created,
    reply_time,
    id_task,
    ts_task_twilio_created
  FROM
    messages_w_tasks_ranked
  WHERE
    rn = 1
),
ai_without_spoc_ranked AS (
  SELECT
  COALESCE(c_cast.id_channel, c_hash.id_channel, c_sss.id_channel) AS id_channel,
  m.id_message,
  m.id_sauron_session AS id_session,
  m.id_sss_session,
  COALESCE(m.id_user, c_cast.id_user, c_hash.id_user, c_sss.id_user) AS id_user,
  COALESCE(c_cast.origin, c_hash.origin, c_sss.origin) AS origin,
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
  NULL AS ts_task_twilio_created,
  ROW_NUMBER() OVER (PARTITION BY m.id_message ORDER BY COALESCE(c_cast.ts_created, c_hash.ts_created, c_sss.ts_created) DESC) AS rn
FROM
  datalake_chatbot.messages AS m
LEFT JOIN
  datalake_customer_support.chats AS c_cast
    ON c_cast.id_session = TRY_CAST(m.id_sauron_session AS BIGINT)
    AND MAKE_DATE(c_cast.year, c_cast.month, c_cast.day) >= '{load_start_date}'
LEFT JOIN
  datalake_customer_support.chats AS c_hash
    ON c_hash.id_sss_session = m.id_sauron_session
    AND MAKE_DATE(c_hash.year, c_hash.month, c_hash.day) >= '{load_start_date}'
LEFT JOIN
  datalake_customer_support.chats AS c_sss
    ON c_sss.id_sss_session = m.id_sss_session
    AND MAKE_DATE(c_sss.year, c_sss.month, c_sss.day) >= '{load_start_date}'
WHERE
  m.conversation_type = 'HUMAN-AI'
),
ai_without_spoc AS (
  SELECT DISTINCT
    id_channel,
    id_message,
    id_session,
    id_sss_session,
    id_user,
    origin,
    message,
    user_type,
    conversation_type,
    reply_time,
    ts_created,
    id_task,
    ts_task_twilio_created
  FROM
    ai_without_spoc_ranked
  WHERE
    rn = 1
),
human_without_spoc_ranked AS (
  SELECT
  COALESCE(c_cast.id_channel, c_hash.id_channel, c_sss.id_channel) AS id_channel,
  m.id_message,
  m.id_sauron_session AS id_session,
  m.id_sss_session,
  COALESCE(m.id_user, c_cast.id_user, c_hash.id_user, c_sss.id_user) AS id_user,
  COALESCE(c_cast.origin, c_hash.origin, c_sss.origin) AS origin,
  m.message,
  CASE WHEN m.role LIKE 'HUMAN' THEN 'User'
    WHEN m.role LIKE 'ANALYST' THEN 'Analyst'
    WHEN m.role LIKE 'SYSTEM' THEN 'Bot'
  ELSE m.role
  END AS user_type,
  m.conversation_type,
  m.reply_time,
  m.ts_created,
  COALESCE(c_cast.id_task, c_hash.id_task, c_sss.id_task) AS id_task,
  COALESCE(c_cast.ts_created, c_hash.ts_created, c_sss.ts_created) AS ts_task_twilio_created,
  ROW_NUMBER() OVER (PARTITION BY m.id_message ORDER BY COALESCE(c_cast.ts_created, c_hash.ts_created, c_sss.ts_created) DESC) AS rn
FROM
  datalake_chatbot.messages AS m
LEFT JOIN
  datalake_customer_support.chats AS c_cast
    ON c_cast.id_session = TRY_CAST(m.id_sauron_session AS BIGINT)
    AND m.ts_created >= c_cast.ts_created
    AND m.ts_created <= c_cast.ts_ended
    AND MAKE_DATE(c_cast.year, c_cast.month, c_cast.day) >= '{load_start_date}'
LEFT JOIN
  datalake_customer_support.chats AS c_hash
    ON c_hash.id_sss_session = m.id_sauron_session
    AND m.ts_created >= c_hash.ts_created
    AND m.ts_created <= c_hash.ts_ended
    AND MAKE_DATE(c_hash.year, c_hash.month, c_hash.day) >= '{load_start_date}'
LEFT JOIN
  datalake_customer_support.chats AS c_sss
    ON c_sss.id_sss_session = m.id_sss_session
    AND m.ts_created >= c_sss.ts_created
    AND m.ts_created <= c_sss.ts_ended
    AND MAKE_DATE(c_sss.year, c_sss.month, c_sss.day) >= '{load_start_date}'
WHERE
  m.conversation_type = 'HUMAN-HUMAN'
),
human_without_spoc AS (
  SELECT
    id_channel,
    id_message,
    id_session,
    id_sss_session,
    id_user,
    origin,
    message,
    user_type,
    conversation_type,
    reply_time,
    ts_created,
    id_task,
    ts_task_twilio_created
  FROM
    human_without_spoc_ranked
  WHERE
    rn = 1
),
all_without_spoc AS (
  SELECT
    id_channel,
    id_message,
    id_session,
    id_sss_session,
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
    id_sss_session,
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
    id_sss_session,
    CAST(COALESCE(id_user, -1) AS BIGINT) AS id_user,
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
    id_sss_session,
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
),
final_ranked AS (
  SELECT
    id_message,
    id_channel AS sk_channel,
    MD5(id_message) AS sk_message,
    id_task AS sk_task,
    id_session AS sk_session,
    id_sss_session AS sk_support_session,
    id_user AS sk_user_sender,
    origin,
    user_type,
    message,
    ROW_NUMBER() OVER(PARTITION BY COALESCE(id_session, id_sss_session) ORDER BY ts_created) AS message_index,
    reply_time,
    ts_created,
    ts_task_twilio_created,
    NOW() AS ts_load,
    ROW_NUMBER() OVER(PARTITION BY id_message ORDER BY ts_created DESC) AS rn
  FROM
    all_messages_with_tasks
)
SELECT
  sk_channel,
  sk_message,
  sk_task,
  sk_session,
  sk_support_session,
  sk_user_sender,
  origin,
  user_type,
  message,
  message_index,
  reply_time,
  ts_created,
  ts_task_twilio_created,
  ts_load
FROM
  final_ranked
WHERE
  rn = 1
