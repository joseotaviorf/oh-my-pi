WITH message_events AS (
  SELECT
    id_channel,
    id_message,
    REPLACE(REPLACE(id_user_external,'_2E', '.'), '_40', '@') AS msg_sender,
    message AS message_body,
    "CHAT INAPP" AS origin,
    ts_created
  FROM
    datalake_internal_chat_clean.internal_chat_messages
  WHERE
    ts_created >= "2022-01-01"
  UNION ALL
  SELECT
    id_channel,
    GET_JSON_OBJECT(event_payload, "$.MessageSid") AS id_message,
    REPLACE(REPLACE(GET_JSON_OBJECT(event_payload, '$.From'),'_2E', '.'), '_40', '@') AS msg_sender,
    message_body,
    "WHATSAPP" AS origin,
    ts_created
  FROM
    datalake_quinto_messenger_clean.channel_event
  WHERE
    ts_created >= "2022-01-01"
),
message_tasks AS (
  SELECT
    t.id_task,
    me.id_message,
    me.msg_sender,
    me.message_body,
    me.origin,
    LAG(me.ts_created) OVER (PARTITION BY t.id_task ORDER BY me.ts_created) AS last_ts,
    me.ts_created
  FROM
    message_events AS me
  INNER JOIN
    datalake_quinto_messenger.tasks AS t
      ON me.id_channel = t.id_channel
)
SELECT
  id_task,
  id_message,
  msg_sender,
  message_body,
  CASE
    WHEN last_ts IS NOT NULL THEN DATEDIFF(SECOND, last_ts, ts_created)
    ELSE NULL
  END AS reply_time,
  origin,
  ts_created
FROM
  message_tasks
