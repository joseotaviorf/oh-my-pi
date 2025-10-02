WITH orchestrator_sessions AS (
  SELECT DISTINCT
    cs.id AS id_session,
    cs.id_external,
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
    s.status,
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
escalated_sessions AS (
  SELECT DISTINCT
    cs.id_ticket,
    cs.id_session,
    cs.first_queue,
    cs.last_queue
  FROM
    datalake_customer_support.tickets AS cs
  INNER JOIN
    orchestrator_sessions AS bs
      ON cs.id_session = bs.id_sauron_session
  WHERE
    cs.front_or_back = 'front'
    AND cs.ticket_origin IN ('call in app', 'whatsapp', 'chat in app')
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY cs.id_session ORDER BY cs.ts_updated DESC) = 1
),
support_sessions AS (
  SELECT
    os.id_session,
    os.id_sauron_session,
    os.id_external,
    es.id_ticket,
    os.id_user,
    os.bot,
    os.status,
    es.first_queue,
    es.last_queue,
    es.id_session IS NOT NULL AS is_escalation,
    os.ts_created,
    Os.ts_updated
  FROM
    orchestrator_sessions AS os
  LEFT JOIN
    escalated_sessions AS es
      ON es.id_session = os.id_sauron_session
)
SELECT DISTINCT
  id_session,
  id_sauron_session,
  id_external,
  id_ticket,
  id_user,
  bot,
  status,
  first_queue,
  last_queue,
  is_escalation,
  ts_created,
  ts_updated
FROM
  support_sessions