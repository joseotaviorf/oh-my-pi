WITH task_queues AS (
  SELECT
    id_task,
    id_queue,
    queue_name
  FROM
    datalake_quinto_messenger_clean.task_event
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" - INTERVAL 30 DAY AND "{load_end_date}"
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_updated DESC) = 1
),
inapp_sessions AS (
  SELECT DISTINCT
    id_chat,
    CAST(id_session AS INTEGER) AS id_session
  FROM
    datalake_quinto_messenger_clean.chat
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
),
whatsapp_sessions AS (
  SELECT DISTINCT
    id_channel,
    CAST(id_session AS INTEGER) AS id_session
  FROM
    datalake_quinto_messenger_clean.channel
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
),
sauron_sessions AS (
  SELECT
    id AS id_session,
    user_data:["user_id"] AS id_user,
    user_data:["user_phone"] AS user_phone,
    user_data:["user_email"] AS user_email
  FROM
    datalake_sauron_clean.session
  WHERE
    year >= YEAR(DATE("{load_start_date}") - INTERVAL 1 YEAR) -- we need to check all sessions as they do not have a fixed lifetime
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_session ORDER BY ts_updated DESC) = 1
),
tasks AS (
  SELECT
    id_channel,
    id_chat,
    id_task,
    id_worker,
    worker_email,
    CASE
      WHEN channel_type = 'whatsapp' THEN REPLACE(customer_contact_info, "whatsapp:+", "")
      ELSE NULL
    END AS from_phone_number,
    REPLACE(twilio_phone_number, "whatsapp:+", "") AS twilio_phone_number,
    customer_email,
    channel_type,
    task_status,
    GET_JSON_OBJECT(conversation_attributes,'$.outcome') AS task_outcome,
    completion_reason AS task_completion_reason,
    channel_status,
    bpo_name,
    assigned_to,
    seconds_to_first_response,
    is_forwarded,
    GET_JSON_OBJECT(conversation_attributes,'$.conversation_attribute_2') AS is_per_team_task,
    ts_created,
    ts_updated,
    task_attributes
  FROM
    datalake_quinto_messenger_clean.task
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_updated DESC) = 1
)
SELECT
  t.id_channel,
  t.id_task,
  CAST(COALESCE(ias.id_session, ws.id_session) AS STRING) AS id_session,
  ss.id_user,
  t.id_worker,
  tq.id_queue,
  tq.queue_name,
  COALESCE(ss.user_email, t.customer_email) AS customer_email,
  COALESCE(ss.user_phone, t.from_phone_number) AS customer_phone_number,
  t.twilio_phone_number,
  CASE
    WHEN ias.id_session IS NOT NULL THEN 'in app'
    WHEN ws.id_session IS NOT NULL THEN 'whatsapp'
  END AS origin,
  t.worker_email,
  t.channel_type,
  t.task_status,
  t.task_outcome,
  t.task_completion_reason,
  t.bpo_name,
  t.seconds_to_first_response,
  t.is_forwarded,
  t.is_per_team_task,
  t.ts_created,
  t.ts_updated AS ts_ended,
  t.task_attributes,
  YEAR(t.ts_created) AS year,
  MONTH(t.ts_created) AS month,
  DAY(t.ts_created) AS day
FROM
  tasks AS t
LEFT JOIN
  inapp_sessions AS ias
    ON ias.id_chat = t.id_chat
LEFT JOIN
  whatsapp_sessions AS ws
    ON ws.id_channel = t.id_channel
LEFT JOIN
  task_queues AS tq
    ON tq.id_task = t.id_task
LEFT JOIN
  sauron_sessions AS ss
    ON ss.id_session = ias.id_session
    OR ss.id_session = ws.id_session
