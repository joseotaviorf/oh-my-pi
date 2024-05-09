
WITH tasks AS (
  SELECT
    id_task,
    id_channel,
    id_chat,
    id_worker,
    REPLACE(SPLIT(customer_metadata, ":")[1], '"', "") AS id_user,
    task_status,
    REPLACE(customer_contact_info, "whatsapp:+", "") AS customer_contact_info,
    customer_email,
    REPLACE(twilio_phone_number, "whatsapp:+", "") AS twilio_phone_number,
    worker_email,
    channel_type,
    completion_reason AS task_completion_reason,
    channel_status,
    bpo_name,
    tags,
    conversation_attributes,
    task_attributes,
    task_resource,
    assigned_to,
    seconds_to_first_response,
    is_forwarded,
    ts_created,
    ts_updated
  FROM
    datalake_quinto_messenger_clean.task
  WHERE
    year >= 2023
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_updated DESC) = 1
),
task_events AS (
  SELECT
    id_task,
    id_queue,
    id_event,
    queue_name,
    event_type,
    ts_created
  FROM
    datalake_quinto_messenger_clean.task_event
  WHERE
    year >= 2023
),
chat_sessions AS (
  SELECT DISTINCT
    id_channel,
    id_session
  FROM
    datalake_quinto_messenger_clean.chat
  WHERE
    year >= 2023
  UNION ALL
  SELECT DISTINCT
    id_channel,
    id_session
  FROM
    datalake_quinto_messenger_clean.channel
  WHERE
    year >= 2023
)
SELECT
  te.id_event,
  t.id_task,
  t.id_channel,
  te.id_queue,
  t.id_chat,
  cs.id_session,
  t.id_worker,
  t.id_user,
  te.queue_name,
  t.task_status,
  te.event_type,
  t.customer_contact_info,
  t.customer_email,
  t.twilio_phone_number,
  t.worker_email,
  t.channel_type,
  t.task_completion_reason,
  t.channel_status,
  t.bpo_name,
  t.tags,
  t.conversation_attributes,
  t.task_attributes,
  t.task_resource,
  t.seconds_to_first_response,
  t.is_forwarded,
  te.ts_created AS ts_event,
  t.ts_created AS ts_task_created,
  t.ts_updated AS ts_task_updated
FROM
  tasks AS t
LEFT JOIN
  chat_sessions AS cs
    ON cs.id_channel = t.id_channel
LEFT JOIN
  task_events AS te
    ON te.id_task = t.id_task
