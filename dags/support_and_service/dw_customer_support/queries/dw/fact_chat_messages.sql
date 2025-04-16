WITH messages AS (
  SELECT DISTINCT
    id_channel,
    GET_JSON_OBJECT(event_payload, "$.MessageSid") AS id_message,
    REPLACE(from_phone_number, 'whatsapp:', '') AS user_sender,
    message_body AS message,
    'whatsapp' AS origin,
    ts_created
  FROM
    datalake_quinto_messenger_clean.channel_event
  WHERE
    year >= YEAR(DATE('{load_start_date}'))
    AND month >= MONTH(DATE('{load_start_date}'))
    AND day >= DAY(DATE('{load_start_date}'))
    AND year <= YEAR(DATE('{load_end_date}'))
    AND month <= MONTH(DATE('{load_end_date}'))
    AND day <= DAY(DATE('{load_end_date}'))
  UNION ALL
  SELECT DISTINCT
    id_channel,
    id_message,
    REPLACE(REPLACE(id_user_external,'_2E', '.'), '_40', '@') AS user_sender,
    message,
    'in_app' AS origin,
    ts_created
  FROM
    datalake_internal_chat_clean.internal_chat_messages
  WHERE
    year >= YEAR(DATE('{load_start_date}'))
    AND month >= MONTH(DATE('{load_start_date}'))
    AND day >= DAY(DATE('{load_start_date}'))
    AND year <= YEAR(DATE('{load_end_date}'))
    AND month <= MONTH(DATE('{load_end_date}'))
    AND day <= DAY(DATE('{load_end_date}'))
),
twilio_data AS (
  SELECT DISTINCT
    m.id_channel,
    COALESCE(ch.id_session, cht.id_session) AS id_session,
    COALESCE(t1.id_task, t2.id_task) AS id_task,
    m.id_message,
    REPLACE(m.user_sender, '+', '') AS user_sender,
    m.origin,
    m.message,
    m.ts_created
  FROM
    messages AS m
  LEFT JOIN
    datalake_quinto_messenger_clean.channel AS ch
      ON ch.id_channel = m.id_channel
      AND ch.ts_created >= '{load_start_date}' - INTERVAL 60 DAY
  LEFT JOIN
    datalake_quinto_messenger_clean.chat AS cht
      ON cht.id_channel = m.id_channel
      AND cht.ts_created >= '{load_start_date}' - INTERVAL 60 DAY
  LEFT JOIN
    datalake_quinto_messenger_clean.task AS t1
      ON t1.id_channel = ch.id_channel
      AND m.origin = 'whatsapp'
      AND t1.ts_created >= '{load_start_date}' - INTERVAL 60 DAY
  LEFT JOIN
    datalake_quinto_messenger_clean.task AS t2
      ON t2.id_chat = cht.id_chat
      AND m.origin = 'in app'
      AND t2.ts_created >= '{load_start_date}' - INTERVAL 60 DAY
)
SELECT DISTINCT
  td.id_channel AS sk_channel,
  COALESCE(td.id_session, ss.id) AS sk_session,
  td.id_message AS sk_message,
  CASE
    WHEN COALESCE(u1.id, u2.id, td.user_sender) = 'system' THEN -1
    ELSE COALESCE(u1.id, u2.id, u3.id, -1)
  END AS sk_user_sender,
  td.origin,
  td.message,
  td.ts_created,
  NOW() AS ts_load
FROM
  twilio_data AS td
LEFT JOIN
  datalake_sauron_clean.session AS ss
    ON td.id_task = ss.source_identity
    AND ss.ts_created >= DATE('{load_start_date}') - INTERVAL 1 YEAR
LEFT JOIN
  datalake_ebdb_user.user AS u1
    ON u1.email = td.user_sender
    AND CONTAINS(td.user_sender, '@')
    AND u1.country_code = 'BR'
LEFT JOIN
  datalake_ebdb_user.user AS u2
    ON REPLACE(u2.main_phone, '+', '') = td.user_sender
    AND u2.country_code = 'BR'
LEFT JOIN
  datalake_ebdb_user.user AS u3
    ON u3.id = td.user_sender