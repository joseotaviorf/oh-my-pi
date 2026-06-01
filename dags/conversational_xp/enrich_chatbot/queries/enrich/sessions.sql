WITH langfuse AS (
  SELECT DISTINCT
    t.id_session,
    FIRST_VALUE(t.version) OVER (
      PARTITION BY t.id_session ORDER BY t.ts_created DESC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS version,
    FIRST_VALUE(
      COALESCE(
        GET_JSON_OBJECT(o.input, '$.metadata.metadata.queue_name'),
        GET_JSON_OBJECT(o.input, '$.last_bot_message.metadata.queue_name'),
        GET_JSON_OBJECT(o.input, '$.department_name')
      )
    ) IGNORE NULLS OVER (
      PARTITION BY t.id_session ORDER BY o.ts_started DESC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS queue_name
  FROM
    datalake_langfuse_clean.traces AS t
  INNER JOIN
    datalake_langfuse_clean.observations AS o
      ON o.id_trace = t.id_trace
  WHERE
    t.ts_created >= DATE('{load_start_date}') - INTERVAL 7 DAY
    AND o.ts_started >= DATE('{load_start_date}') - INTERVAL 7 DAY
),
chatbot_sessions AS (
  SELECT
    cs.id AS id_session,
    cs.id_external AS id_langfuse_session,
    sss.public_id AS id_sss_session,
    CAST(cs.id_sauron_session AS BIGINT) AS id_sauron_session,
    cs.id_user,
    CASE
      WHEN m.channel = 'WHATSAPP_SONIA_CHAT' THEN 'sonia'
      WHEN m.channel IN ('IN_APP_SUPPORT_CHAT', 'WHATSAPP_SUPPORT_CHAT') THEN 'wall-e'
      WHEN m.channel = 'WHATSAPP_MATTHEW_CHAT' THEN 'matthew'
      WHEN m.channel = 'WHATSAPP_CONCIERGE_CHAT' THEN 'concierge'
      WHEN m.channel = 'COPILOT_CHAT' THEN 'copilot'
      WHEN m.channel = 'WHATSAPP_FORSALE_TRANSACT_EOP_CHAT' THEN 'vandinha'
      WHEN m.channel = 'WHATSAPP_CLAUDIA_CHAT' THEN 'claudia'
      WHEN m.channel = 'WHATSAPP_ALIAS_CHAT' THEN 'alias'
      WHEN m.channel = 'WHATSAPP_DOMINIC_CHAT' THEN 'dominic'
      WHEN m.channel LIKE '%ISAIAS%' THEN 'isaias'
      ELSE 'unknown'
    END AS bot,
    COALESCE(sss.source, s.source) AS source,
    COALESCE(sss.source_env, s.source_environment) AS source_environment,
    COALESCE(sss.status, s.status) AS status,
    COALESCE(
      cs.user_phone_number,
      sss.user_phone,
      s.user_phone,
      sss.user_data:["user_phone"],
      s.user_data:["user_phone"]
    ) AS user_phone_number,
    cs.ts_created,
    COALESCE(sss.ts_updated, s.ts_updated) AS ts_updated
  FROM
    datalake_copilot_service_clean.session AS cs
  INNER JOIN
    datalake_copilot_service_clean.message AS m
      ON m.id_session = cs.id
  LEFT JOIN
    datalake_support_session_service_clean.support_session AS sss
      ON sss.public_id = cs.id_sauron_session
  LEFT JOIN
    datalake_sauron_clean.session AS s
      ON s.id = CAST(cs.id_sauron_session AS BIGINT)
  WHERE
    cs.ts_created >= DATE('{load_start_date}') - INTERVAL 7 DAY
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY cs.id ORDER BY cs.ts_created DESC) = 1
),
chats_by_sauron AS (
  SELECT
    c.id_task,
    c.id_session AS id_sauron_session,
    c.queue_name AS last_queue
  FROM
    datalake_customer_support.chats AS c
  WHERE
    c.ts_created >= DATE('{load_start_date}') - INTERVAL 15 DAY
    AND c.id_session IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY c.id_session ORDER BY c.ts_created DESC) = 1
),
chats_by_sss AS (
  SELECT
    c.id_task,
    c.id_sss_session,
    c.queue_name AS last_queue
  FROM
    datalake_customer_support.chats AS c
  WHERE
    c.ts_created >= DATE('{load_start_date}') - INTERVAL 15 DAY
    AND c.id_sss_session IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY c.id_sss_session ORDER BY c.ts_created DESC) = 1
),
tickets AS (
  SELECT
    id_twilio,
    MAX(CAST(id_ticket AS BIGINT)) AS id_ticket
  FROM
    datalake_customer_support.tickets
  WHERE
    channel = 'chat'
    AND id_twilio IS NOT NULL
    AND ts_created >= DATE('{load_start_date}') - INTERVAL 15 DAY
  GROUP BY
    id_twilio
)
SELECT
  s.id_session,
  s.id_sauron_session,
  s.id_langfuse_session,
  s.id_sss_session,
  COALESCE(c_sss.id_task, c_sauron.id_task) AS id_task,
  tk.id_ticket,
  s.id_user,
  s.user_phone_number,
  s.bot,
  CASE
    WHEN s.source = 'whatsapp' THEN s.source
    WHEN s.source = 'internal_chat' THEN 'in app'
    ELSE 'unknown'
  END AS channel,
  CASE
    WHEN s.source = 'whatsapp' AND s.source_environment = 'default' THEN 'main number'
    WHEN s.source = 'whatsapp' AND s.source_environment != 'default' THEN 'others'
    ELSE NULL
  END AS whatsapp_number,
  s.status,
  lf.version,
  CASE WHEN COALESCE(c_sss.id_task, c_sauron.id_task) IS NOT NULL THEN lf.queue_name END AS first_queue,
  REPLACE(COALESCE(c_sss.last_queue, c_sauron.last_queue), '[AeC] ', '') AS last_queue,
  COALESCE(c_sss.id_task, c_sauron.id_task) IS NOT NULL AS is_escalated,
  s.ts_created,
  s.ts_updated
FROM
  chatbot_sessions AS s
LEFT JOIN
  chats_by_sauron AS c_sauron
    ON c_sauron.id_sauron_session = s.id_sauron_session
LEFT JOIN
  chats_by_sss AS c_sss
    ON c_sss.id_sss_session = s.id_sss_session
LEFT JOIN
  langfuse AS lf
    ON lf.id_session = s.id_langfuse_session
LEFT JOIN
  tickets AS tk
    ON tk.id_twilio = COALESCE(c_sss.id_task, c_sauron.id_task)
