WITH call AS (
  WITH twilio_call_flex_events AS (
    SELECT
      id_call,
      id_task,
      id_task_queue,
      id_reservation,
      event_type,
      agent_email,
      task_queue_name,
      IFNULL(LAG(task_queue_name) OVER (PARTITION BY id_task ORDER BY ts_created_local), '-') AS previous_task_queue_name,
      customer_phone,
      ts_created_local AS ts_created
    FROM
      datalake_bigfone_twilio.call_flex_events
    WHERE
      direction = 'inbound'
  ),
  reservations_ts AS (
    SELECT
      tcfe.id_call,
      tcfe.id_task,
      tcfe.id_task_queue,
      tcfe.id_reservation,
      tcfe.agent_email,
      tcfe.previous_task_queue_name,
      tcfe.task_queue_name,
      tcfe.customer_phone,
      tcfe.ts_created
    FROM
      twilio_call_flex_events AS tcfe
    WHERE
      tcfe.task_queue_name != tcfe.previous_task_queue_name
  ),
  /* To check when the reservation/department ended we're adding this CTE to get the next timestamp
  of the department, this way we can attribute the right id_reservation checking the timestamps.
  This check is made in call_received_demand CTE, joining reservations_ts_ended with reservations.*/
  reservations_ts_ended AS (
    SELECT
      *,
      LEAD(ts_created) OVER (PARTITION BY id_task ORDER BY ts_created) AS ts_created_ended
    FROM
      reservations_ts
  ),
  reservations AS (
    SELECT
      id_task,
      id_task_queue,
      id_reservation,
      agent_email,
      ts_created
    FROM
      twilio_call_flex_events
    WHERE
      event_type = 'reservation.accepted'
  ),
  call_received_demand AS(
    SELECT
      rts.id_call,
      rts.id_task,
      r.id_reservation,
      rts.task_queue_name,
      r.agent_email,
      rts.customer_phone,
      rts.ts_created
    FROM
      reservations_ts_ended AS rts
    LEFT JOIN
      reservations AS r
        ON rts.id_task = r.id_task
        AND rts.id_task_queue = r.id_task_queue
        and r.ts_created >= rts.ts_created
        AND r.ts_created < COALESCE(rts.ts_created_ended, CURRENT_TIMESTAMP())
    WHERE
      task_queue_name <> previous_task_queue_name
  )
  SELECT
    crd.id_call,
    NULL AS id_session,
    NULL AS id_ticket,
    crd.id_task,
    crd.agent_email,
    'call' AS channel,
    crd.customer_phone,
    crd.task_queue_name AS department,
    call.id_external_service IS NOT NULL AS is_answered,
    crd.ts_created,
    NULL AS ts_updated
  FROM
    call_received_demand AS crd
  LEFT JOIN
    datalake_customer_support.call
      ON crd.id_task = call.id_external_service
      AND crd.id_reservation = call.id_segment
),

chat AS (
  WITH task_event as (
    SELECT
      te.id_task_external,
      t.id_channel_external,
      GET_JSON_OBJECT(t.task_attributes,'$.chat_id') AS id_chat,
      te.event_type,
      GET_JSON_OBJECT(te.event_payload,'$.TaskQueueName') AS task_queue_name,
      GET_JSON_OBJECT(event_payload,'$.WorkerAttributes.email') AS agent_email,
      REGEXP_REPLACE(REGEXP_EXTRACT(GET_JSON_OBJECT(t.task_attributes,'$.from'), '(\\w+:)(.+)', 2), '^(\\+)(.*)', '') AS customer_phone,
      GET_JSON_OBJECT(te.event_payload,'$.TaskAttributes.conversations.conversation_measure_1') IS NOT NULL AS is_answered,
      te.ts_created,
      te.ts_updated
    FROM
      datalake_quinto_messenger_clean.task AS t
    INNER JOIN
      datalake_quinto_messenger_clean.task_event AS te
        ON te.id_task_external = t.id_external
  ),
  created_events as (
    SELECT
      id_task_external,
      customer_phone,
      ts_created
    FROM
      task_event
    WHERE
      event_type = 'reservation.created'
  ),
  chat_received_demand AS (
    SELECT
      ce.id_task_external,
      chn.id_source AS id_session_whats,
      c.id_session AS id_session_inapp,
      te.is_answered,
      te.task_queue_name,
      IFNULL(LEAD(te.task_queue_name) OVER (PARTITION BY te.id_task_external ORDER BY te.ts_created), '-') AS next_task_queue_name,
      te.agent_email,
      ce.customer_phone,
      ce.ts_created,
      te.ts_updated
    FROM
      created_events AS ce
    INNER JOIN
      task_event AS te
        ON ce.id_task_external = te.id_task_external
    LEFT JOIN
      datalake_quinto_messenger.channel AS chn
        ON chn.id_channel = te.id_channel_external
    LEFT JOIN
      datalake_quinto_messenger.chat AS c
        ON c.id_chat = te.id_chat
  )
  SELECT
    NULL AS id_call,
    COALESCE(crd.id_session_whats, crd.id_session_inapp) AS id_session,
    NULL AS id_ticket,
    crd.id_task_external AS id_task,
    crd.agent_email,
    'chat' AS channel,
    crd.customer_phone,
    crd.task_queue_name AS department,
    crd.is_answered,
    crd.ts_created,
    crd.ts_updated
  FROM
    chat_received_demand AS crd
  WHERE
    task_queue_name != next_task_queue_name
),

email AS (
  SELECT
    NULL AS id_call,
    NULL AS id_session,
    id_ticket,
    NULL AS id_task,
    agent_email,
    'email' AS channel,
    NULL AS customer_phone,
    department,
    true AS is_answered,
    ts_ticket_started AS ts_created,
    NULL AS ts_updated
  FROM
    datalake_customer_support.email
  WHERE
    direction = 'inbound'
    AND front_or_back = 'front'
)
SELECT
  *
FROM
  call
UNION ALL
SELECT
  *
FROM
  chat
UNION ALL
SELECT
  *
FROM
  email
