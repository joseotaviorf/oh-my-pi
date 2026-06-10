WITH ai_messages AS (
  SELECT DISTINCT
    -- copilot key is either the numeric sauron id or the SSS public id (uuid)
    TRY_CAST(s.id_sauron_session AS BIGINT) AS id_sauron_session,
    CASE
      WHEN TRY_CAST(s.id_sauron_session AS BIGINT) IS NULL THEN s.id_sauron_session
    END AS id_sss_session,
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
    COALESCE(CAST(id_sauron_session AS STRING), id_sss_session) AS id_session_key,
    COUNT(*) AS total_messages
  FROM
    ai_messages
  WHERE
    role != 'HARDCODED'
  GROUP BY 1
),
-- chat.id_session for source = 'sauron' holds either the numeric sauron id
-- or sauron's public_id (uuid); resolve hashes to the numeric id
sauron_chats AS (
  SELECT DISTINCT
    c.id_channel,
    COALESCE(TRY_CAST(c.id_session AS BIGINT), srn.id) AS id_sauron_session,
    CASE
      WHEN TRY_CAST(c.id_session AS BIGINT) IS NULL THEN c.id_session
    END AS id_sauron_session_hash
  FROM
    datalake_quinto_messenger_clean.chat AS c
  LEFT JOIN
    datalake_sauron_clean.session AS srn
      ON srn.public_id = c.id_session
  WHERE
    c.source = 'sauron'
),
-- chat.id_session for source = 'support_session' is the SSS public_id (uuid)
sss_chats AS (
  SELECT DISTINCT
    c.id_channel,
    c.id_session AS id_sss_session
  FROM
    datalake_quinto_messenger_clean.chat AS c
  WHERE
    c.source = 'support_session'
),
-- a channel maps to many chat sessions over time; pick the one whose active
-- window contains the message timestamp so each id_message resolves to a single
-- session and the downstream MERGE on id_message never sees duplicate keys
whatsapp_channel_session AS (
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
      datalake_quinto_messenger_clean.channel AS c
        ON c.id_channel = ce.id_channel
    WHERE
      MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
  ) AS ranked_channel
  WHERE
    session_rank = 1
),
whatsapp_sauron_session AS (
  SELECT
    id_message,
    id_sauron_session,
    id_sauron_session_hash
  FROM (
    SELECT
      ce.id AS id_message,
      COALESCE(TRY_CAST(c.id_session AS BIGINT), srn.id) AS id_sauron_session,
      CASE
        WHEN TRY_CAST(c.id_session AS BIGINT) IS NULL THEN c.id_session
      END AS id_sauron_session_hash,
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
      datalake_quinto_messenger_clean.chat AS c
        ON c.id_channel = ce.id_channel
        AND c.source = 'sauron'
    LEFT JOIN
      datalake_sauron_clean.session AS srn
        ON srn.public_id = c.id_session
    WHERE
      MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
  ) AS ranked_sauron_chat
  WHERE
    session_rank = 1
),
whatsapp_sss_session AS (
  SELECT
    id_message,
    id_sss_session
  FROM (
    SELECT
      ce.id AS id_message,
      c.id_session AS id_sss_session,
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
      datalake_quinto_messenger_clean.chat AS c
        ON c.id_channel = ce.id_channel
        AND c.source = 'support_session'
    WHERE
      MAKE_DATE(ce.year, ce.month, ce.day) >= '{load_start_date}'
  ) AS ranked_sss_chat
  WHERE
    session_rank = 1
),
whatsapp_messages AS (
  SELECT DISTINCT
    ce.id_channel,
    ce.id AS id_message,
    COALESCE(wss.id_sauron_session, TRY_CAST(wcs.id_session AS BIGINT)) AS id_sauron_session,
    COALESCE(wsss.id_sss_session, wss.id_sauron_session_hash) AS id_sss_session,
    REPLACE(REPLACE(REPLACE(ce.from_phone_number, 'whatsapp:', ''), '_2E', '.'), '_40', '@') AS user_sender,
    ce.message_body AS message,
    ce.ts_created,
    CASE
        WHEN ce.from_phone_number = 'system' THEN 'SYSTEM'
        WHEN ce.from_phone_number LIKE '%whatsapp%' THEN 'HUMAN'
        WHEN REPLACE(REPLACE(ce.from_phone_number,'_2E', '.'), '_40', '@')  LIKE '%@%' THEN 'ANALYST'
        WHEN ce.from_phone_number LIKE '%@%' THEN 'ANALYST'
        ELSE NULL
      END AS role
  FROM
    datalake_quinto_messenger_clean.channel_event AS ce
  LEFT JOIN
    -- legacy source kept as fallback: some channels never receive a chat row,
    -- so chat-derived keys take precedence and channel.id_session fills gaps
    whatsapp_channel_session AS wcs
      ON wcs.id_message = ce.id
  LEFT JOIN
    whatsapp_sauron_session AS wss
      ON wss.id_message = ce.id
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
    MAX(schat.id_sauron_session) AS id_sauron_session,
    MAX(COALESCE(sschat.id_sss_session, schat.id_sauron_session_hash)) AS id_sss_session,
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
    sauron_chats AS schat
      ON schat.id_channel = icm.id_channel
  LEFT JOIN
    sss_chats AS sschat
      ON sschat.id_channel = icm.id_channel
  WHERE
    MAKE_DATE(icm.year, icm.month, icm.day) >= '{load_start_date}'
  GROUP BY ALL
),
-- id_session_key is the unified session identity: the numeric sauron id when
-- known, otherwise the hash (SSS public id or unresolved sauron public id)
messages AS (
  SELECT
    id_message,
    id_sauron_session,
    id_sss_session,
    COALESCE(CAST(id_sauron_session AS STRING), id_sss_session) AS id_session_key,
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
    id_sss_session,
    COALESCE(CAST(id_sauron_session AS STRING), id_sss_session) AS id_session_key,
    user_sender,
    message,
    role,
    ts_created
  FROM
    inapp_messages
),
messages_trimmed AS (
  SELECT
    m.id_message,
    m.id_sauron_session,
    m.id_sss_session,
    m.id_session_key,
    m.user_sender,
    m.message,
    m.role,
    m.ts_created
  FROM
    messages AS m
  LEFT JOIN
    ai_message_count AS amc
      ON amc.id_session_key = m.id_session_key
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY m.id_session_key ORDER BY m.ts_created) > COALESCE(amc.total_messages, 0)
),
messages_w_users AS (
  SELECT DISTINCT
    m.id_message,
    m.id_sauron_session,
    m.id_sss_session,
    m.id_session_key,
    CASE
      WHEN m.user_sender = 'system' THEN -1
      WHEN m.role = 'ANALYST' THEN u1.id
      WHEN COALESCE(s.user_data:["user_id"], sss.user_data:["user_id"]) IS NOT NULL 
        AND m.role = 'HUMAN' THEN COALESCE(s.user_data:["user_id"], sss.user_data:["user_id"])
      WHEN u1.id IS NOT NULL THEN u1.id
      WHEN STARTSWITH(m.user_sender, '+') THEN NULL
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
    datalake_support_session_service_clean.support_session AS sss
      ON sss.public_id = m.id_sss_session
  LEFT JOIN
    datalake_ebdb_user.user AS u1
      ON u1.email = m.user_sender
      AND CONTAINS(m.user_sender, '@')
      AND u1.country_code = 'BR'
),
all_messages AS (
  SELECT
    id_message,
    id_sauron_session,
    id_sss_session,
    id_session_key,
    id_user,
    message,
    CASE
      WHEN MIN(CASE WHEN role = 'ANALYST' THEN ts_created END)
        OVER(PARTITION BY id_session_key) IS NULL THEN 'HUMAN-AI'
      WHEN ts_created < MIN(CASE WHEN role = 'ANALYST' THEN ts_created END)
        OVER(PARTITION BY id_session_key) THEN 'HUMAN-AI'
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
    id_sss_session,
    COALESCE(CAST(id_sauron_session AS STRING), id_sss_session) AS id_session_key,
    id_user,
    message,
    'HUMAN-AI' AS conversation_type,
    role,
    ts_created
  FROM 
    ai_messages
),
-- spoc flag aggregated per session key; sauron ids (numeric) and
-- sss ids (hash) are disjoint key spaces, so both live in one column
spoc_sessions AS (
  SELECT
    id_session AS id_chat_session,
    MAX(is_spoc_task) AS is_spoc_session
  FROM
    datalake_customer_support.chats
  WHERE
    ts_created >= '{load_start_date}'
    AND id_session IS NOT NULL
  GROUP BY 1
  UNION ALL
  SELECT
    id_sss_session AS id_chat_session,
    MAX(is_spoc_task) AS is_spoc_session
  FROM
    datalake_customer_support.chats
  WHERE
    ts_created >= '{load_start_date}'
    AND id_sss_session IS NOT NULL
  GROUP BY 1
)
SELECT DISTINCT
  am.id_message,
  CAST(am.id_sauron_session AS STRING) AS id_sauron_session,
  am.id_sss_session,
  am.id_user,
  am.message,
  ROW_NUMBER() OVER(PARTITION BY am.id_session_key ORDER BY am.ts_created) AS message_index,
  am.conversation_type,
  am.role,
  CASE
    WHEN LAG(am.ts_created) OVER(PARTITION BY am.id_session_key ORDER BY am.ts_created) IS NOT NULL
      AND LAG(am.role) OVER(PARTITION BY am.id_session_key ORDER BY am.ts_created) != role
        THEN DATE_DIFF(
          SECOND,
          LAG(am.ts_created) OVER (PARTITION BY am.id_session_key ORDER BY am.ts_created),
          am.ts_created
        )
    ELSE NULL
  END AS reply_time,
  am.ts_created
FROM 
  all_messages AS am
LEFT JOIN
  spoc_sessions AS ss
    ON ss.id_chat_session = am.id_session_key
WHERE
  am.id_session_key IS NOT NULL
  AND ss.is_spoc_session IS NOT TRUE
