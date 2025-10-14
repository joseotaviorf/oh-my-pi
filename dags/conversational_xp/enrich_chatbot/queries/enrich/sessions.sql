WITH orchestrator_sessions AS (
  SELECT DISTINCT
    cs.id AS id_session,
    cs.id_external AS id_langfuse_session,
    s.id AS id_sauron_session,
    cs.id_user,
    CASE
      WHEN m.channel = 'WHATSAPP_SONIA_CHAT' THEN 'sonia'
      WHEN m.channel = 'IN_APP_SUPPORT_CHAT' THEN 'wall-e'
      WHEN m.channel IN ('WHATSAPP_ISAIAS_CHAT', 'WHATSAPP_ISAIAS_MAIN_CHAT') THEN 'isaias'
      WHEN m.channel = 'WHATSAPP_MATTHEW_CHAT' THEN 'matthew'
      WHEN m.channel = 'WHATSAPP_CONCIERGE_CHAT' THEN 'concierge'
      WHEN m.channel = 'COPILOT_CHAT' THEN 'copilot'
      ELSE 'unknown'
    END AS bot,
    s.department AS first_queue,
    s.source,
    s.source_environment,
    COALESCE(s.user_data:["user_phone"], cs.user_phone_number) AS user_phone_number,
    cs.ts_created,
    s.ts_updated
  FROM
    datalake_sauron_clean.session AS s
  INNER JOIN
    datalake_copilot_service_clean.session AS cs
      ON cs.id_sauron_session = s.id
  INNER JOIN
    datalake_copilot_service_clean.message AS m
      ON m.id_session = cs.id
  WHERE
    s.ts_updated >= '{load_start_date}'
),
old_bot_sessions AS (
  SELECT
    gs.id_session,
    ss.user_data:["user_id"] AS id_user,
    'old bot' AS bot,
    ss.department AS first_queue,
    ss.source,
    ss.source_environment,
    ss.user_data:["user_phone"] AS user_phone_number,
    ss.ts_created,
    ss.ts_updated
  FROM
    datalake_greenseer_clean.session AS gs
  LEFT JOIN
    datalake_sauron_clean.session AS ss
      ON ss.id = gs.id_session
  WHERE
    ss.ts_updated >= '{load_start_date}'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_started DESC) = 1
),
sessions AS (
  SELECT
    NULL AS id_session,
    id_session AS id_sauron_session,
    NULL AS id_langfuse_session,
    id_user,
    user_phone_number,
    bot,
    first_queue,
    source,
    source_environment,
    ts_created,
    ts_updated
  FROM
    old_bot_sessions
  UNION ALL
  SELECT
    id_session,
    id_sauron_session,
    id_langfuse_session,
    id_user,
    user_phone_number,
    bot,
    first_queue,
    source,
    source_environment,
    ts_created,
    ts_updated
  FROM
    orchestrator_sessions
),
escalated_sessions AS (
  SELECT DISTINCT
    t.id_ticket,
    t.id_session,
    t.last_queue
  FROM
    datalake_customer_support.tickets AS t
  INNER JOIN
    sessions AS s
      ON t.id_session = s.id_sauron_session
  WHERE
    t.front_or_back = 'front'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY t.id_session ORDER BY t.ts_updated DESC) = 1
)
SELECT
  s.id_session,
  s.id_sauron_session,
  s.id_langfuse_session,
  es.id_ticket,
  s.id_user,
  s.user_phone_number,
  s.bot,
  CASE
    WHEN s.source = 'whatsapp' THEN s.source
    WHEN s.source = 'internal_chat' THEN 'in app'
    ELSE 'unknown'
  END AS channel,
  CASE
    WHEN s.source = 'whatsapp' AND s.source_environment = 'default' THEN 'main'
    WHEN s.source = 'whatsapp' AND s.source_environment != 'default' THEN 'other'
    ELSE NULL
  END AS whatsapp_number,
  s.first_queue,
  es.last_queue,
  s.first_queue IS NOT NULL AS is_escalated,
  s.ts_created,
  s.ts_updated
FROM
  sessions AS s
LEFT JOIN
  escalated_sessions AS es
    ON es.id_session = s.id_sauron_session