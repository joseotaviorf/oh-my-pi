WITH tasks AS (
  SELECT
    id_task,
    id_channel,
    id_chat,
    id_worker,
    REPLACE(SPLIT(customer_metadata, ":")[1], '"', "") AS id_user,
    CASE
      WHEN channel_type = 'whatsapp' THEN REPLACE(customer_contact_info, "whatsapp:+", "")
      ELSE NULL
    END AS from_phone_number,
    REPLACE(twilio_phone_number, "whatsapp:+", "") AS to_phone_number,
    customer_email,
    worker_email,
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
    ts_updated
  FROM
    datalake_quinto_messenger_clean.task
  WHERE
    year >= 2023
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_updated DESC) = 1
),
task_queues AS (
  SELECT
    id_task,
    id_queue,
    queue_name
  FROM
    datalake_quinto_messenger_clean.task_event
  WHERE
    year >= 2023
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_created DESC) = 1
),
inapp_sessions AS (
  SELECT DISTINCT
    id_chat,
    id_session
  FROM
    datalake_quinto_messenger_clean.chat
  WHERE
    year >= 2023
),
whatsapp_sessions AS (
  SELECT DISTINCT
    id_channel,
    id_session
  FROM
    datalake_quinto_messenger_clean.channel
  WHERE
    year >= 2023
)
SELECT
  t.id_task,
  t.id_channel,
  tq.id_queue,
  t.id_chat,
  COALESCE(is.id_session, ws.id_session) AS id_session,
  t.id_worker,
  t.id_user,
  tq.queue_name,
  t.customer_email,
  t.from_phone_number,
  t.to_phone_number,
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
  t.ts_updated AS ts_ended
FROM
  tasks AS t
LEFT JOIN
  inapp_sessions AS is
    ON is.id_chat = t.id_chat
LEFT JOIN
  whatsapp_sessions AS ws
    ON ws.id_channel = t.id_channel
LEFT JOIN
  task_queues AS tq
    ON tq.id_task = t.id_task
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY t.id_task ORDER BY t.ts_updated DESC) = 1
