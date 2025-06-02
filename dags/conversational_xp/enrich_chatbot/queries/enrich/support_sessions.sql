WITH orchestrator_sessions AS (
  SELECT DISTINCT
    s.id AS id_session,
    s.id_sauron_session,
    s.id_user,
    m.channel,
    s.ts_created
  FROM
    datalake_copilot_service_clean.session AS s
  INNER JOIN
    datalake_copilot_service_clean.message AS m
      ON m.id_session = s.id
  WHERE
    s.ts_created >= DATE('{load_start_date}') - INTERVAL 3 MONTH
    AND m.channel = 'IN_APP_SUPPORT_CHAT'
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
    bs.id_session,
    bs.id_sauron_session,
    es.id_ticket,
    bs.id_user,
    es.first_queue,
    es.last_queue,
    es.id_session IS NOT NULL AS is_escalation,
    bs.ts_created,
    ss.ts_updated AS ts_finished
  FROM
    orchestrator_sessions AS bs
  LEFT JOIN
    datalake_sauron_clean.session AS ss
      ON ss.id = bs.id_sauron_session
      AND ss.status = 'expired'
  LEFT JOIN
    escalated_sessions AS es
      ON es.id_session = bs.id_sauron_session
)
SELECT
  id_session,
  id_sauron_session,
  id_ticket,
  id_user,
  first_queue,
  last_queue,
  is_escalation,
  TIMESTAMPDIFF(SECOND, ts_created, ts_finished) AS session_time_sec,
  ts_created,
  ts_finished,
  LAG(ts_created) OVER(PARTITION BY id_user ORDER BY ts_created) AS ts_previous_session
FROM
  support_sessions