WITH message_raw AS (
  SELECT
    id,
    id_channel AS id_channel_external,
    ts_created - INTERVAL 3 HOURS AS ts_created,
    get_json_object(event_payload, '$.Index') AS ordem,
    get_json_object(event_payload, '$.Body') AS message,
    get_json_object(event_payload, '$.From') AS message_from,
    LEAD(id) OVER (PARTITION BY id_channel ORDER BY ts_created) AS next_id,
    CASE
      WHEN
        REGEXP_EXTRACT(
          GET_JSON_OBJECT(event_payload, '$.From'), '((@quintoandar\.com\.br)|(@atento\.com\.br))', 1) != ''
        THEN get_json_object(event_payload, '$.From')
    END AS key_email
  FROM
    datalake_quinto_messenger_clean.channel_event
  WHERE
    MAKE_DATE(year, month, day) >= '{load_start_date}' - INTERVAL 180 DAY
),
next_message AS (
  SELECT
    nm.id,
    nm.next_id,
    nm.message_from,
    mr.ts_created AS next_ts_created,
    mr.message_from AS message_to
  FROM
    message_raw AS nm
  LEFT JOIN
    message_raw AS mr
      ON nm.next_id = mr.id
      AND nm.message_from != mr.message_from
),
tmr_by_message AS (
  SELECT
    mra.id,
    mra.id_channel_external,
    mra.ts_created,
    mra.ordem,
    mra.message,
    mra.message_from,
    mra.key_email,
    nm.next_ts_created,
    nm.message_to,
    CASE
      WHEN
        next_ts_created IS NOT NULL
      THEN TIMESTAMPDIFF(MINUTE, ts_created, next_ts_created)
      ELSE NULL
    END AS minutes_diff_for_answer
  FROM
    message_raw AS mra
  LEFT JOIN
    next_message AS nm
      ON mra.id = nm.id
),
chat_with_minutes_diff AS (
  SELECT
    event.id,
    event.id_channel_external,
    event.ordem,
    event.message,
    event.ts_created,
    event.message_from,
    event.key_email,
    CASE
      WHEN
        LAST_VALUE(event.key_email) IGNORE NULLS OVER (PARTITION BY event.id_channel_external ORDER BY event.ts_created ROWS BETWEEN UNBOUNDED PRECEDING AND 0 FOLLOWING) IS NULL
      THEN event.message_from
      ELSE
        LAST_VALUE(event.key_email) IGNORE NULLS OVER (PARTITION BY event.id_channel_external ORDER BY event.ts_created ROWS BETWEEN UNBOUNDED PRECEDING AND 0 FOLLOWING)
    END AS last_agent_email,
    tbm.message_to,
    tbm.next_ts_created,
    tbm.minutes_diff_for_answer
  FROM
    message_raw AS event
  LEFT JOIN
    tmr_by_message AS tbm
      ON tbm.id = event.id
),
chat_messenger AS (
  SELECT DISTINCT
    t.id_ticket,
    c.id_session,
    channel.id_channel,
    c.worker_email AS agent_email,
    c.queue_name AS department,
    c.ts_created - INTERVAL 3 HOUR AS chat_ts_created,
    c.ts_created - INTERVAL 3 HOUR AS ts_segment_created,
    c.ts_ended - INTERVAL 3 HOUR AS ts_segment_closed
  FROM
    datalake_customer_support.chats AS c
  LEFT JOIN
    datalake_quinto_messenger_clean.channel AS channel
      ON c.id_session = channel.id_session
  LEFT JOIN
    datalake_customer_support.tickets AS t
      ON t.id_session = c.id_session
      AND t.channel = 'chat'
  WHERE
    c.queue_name IN (
      'CX Visitas [FRONT] [PRE]',
      'CX Propostas [FRONT] [PRE]',
      'CX Mudança [FRONT] [POS]',
      'CX Parceiros [FRONT] [PRE]',
      'CX Parceiros da Portaria [FRONT] [PRE]',
      'Consultores imobiliários 5A',
      'CX Ação Plaquinhas [FRONT] [PRE]',
      'CX Pagamentos [FRONT] [POS]',
      'CX Reparos [FRONT] [POS]',
      'CX Rescisão [FRONT] [POS]',
      'CX Parceiros Compra e Venda [FRONT]'
    )
    AND channel.id_channel IS NOT NULL
    AND t.id_ticket IS NOT NULL
)
SELECT
  DATE_TRUNC('day', date(cm.chat_ts_created)) AS dt_created,
  cm.department,
  event.message_to AS analyst,
  CAST(AVG(event.minutes_diff_for_answer) AS DECIMAL(15,3)) AS avg_tmr,
  COUNT(DISTINCT
    CASE
      WHEN event.minutes_diff_for_answer <= 5
        THEN event.id
      ELSE NULL
    END
  ) AS volume_message_less_than_5min,
  COUNT(DISTINCT event.id) AS total_message_volume,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load
FROM
  chat_messenger AS cm
LEFT JOIN
  chat_with_minutes_diff AS event
    ON event.id_channel_external = cm.id_channel
    AND event.last_agent_email = cm.agent_email
    AND event.ts_created >= cm.ts_segment_created
    AND event.ts_created < cm.ts_segment_closed
WHERE
  CAST(cm.chat_ts_created AS DATE) BETWEEN DATE('{load_start_date}') - INTERVAL '90' DAY AND DATE('{load_end_date}')
  AND REGEXP_LIKE(event.message_to, '((@quintoandar\.com\.br)|(@atento\.com\.br))') = true
  AND REGEXP_LIKE(event.message_from, '((@quintoandar\.com\.br)|(@atento\.com\.br))') = false
GROUP BY
  DATE_TRUNC('day', date(cm.chat_ts_created)),
  cm.department,
  event.message_to
