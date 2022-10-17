WITH call AS(
  WITH twilio_call_flex_events AS (
    SELECT
      id_task,
      id_call,
      id_task_queue,
      id_reservation,
      id_agent,
      id_event,
      GET_JSON_OBJECT(metadata,'$.event_data.TaskChannelSid') AS id_channel,
      event_type,
      GET_JSON_OBJECT(metadata,'$.channelType') AS channel_name,
      agent_email,
      location,
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
      tcfe.id_task,
      tcfe.id_call,
      tcfe.id_task_queue,
      tcfe.id_reservation,
      tcfe.id_agent,
      tcfe.id_event,
      tcfe.id_channel,
      tcfe.channel_name,
      tcfe.agent_email,
      tcfe.location,
      tcfe.previous_task_queue_name,
      tcfe.task_queue_name,
      tcfe.customer_phone,
      tcfe.ts_created AS ts_created
    FROM 
      twilio_call_flex_events AS tcfe
    WHERE 
      tcfe.task_queue_name != tcfe.previous_task_queue_name
  ),
  /*
    To check when the reservation/department ended we're adding this CTE to get the next timestamp
      of the department, this way we can attribute the right id_reservation checking the timestamps.
      This check is made in call_received_demand CTE, joining reservations_ts_ended with reservations.
  */
  reservations_ts_ended AS(
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
      id_agent,
      agent_email,
      location,
      ts_created
    FROM
      twilio_call_flex_events
    WHERE 
      event_type = 'reservation.accepted'
  ),
  customer_identification AS (
    SELECT
      REGEXP_REPLACE(customer_contact,'(^\\+?55)|(\\D*)','') AS formatted_phone,
      MAX(id_user) AS id_user
    FROM
      datalake_ebdb_customer_contact_identification.customer_contact_identification
    WHERE
      channel = 'phone'
    GROUP BY 1
  ),
  call_received_demand AS(
    SELECT
      rts.id_task AS id_external_service,
      rts.id_channel,
      rts.id_task_queue,
      r.id_reservation,
      r.id_agent,
      rts.id_event,
      rts.id_call,
      ci.id_user,
      rts.task_queue_name,
      'call' AS channel_name,
      r.agent_email,
      r.location AS agent_location,
      rts.customer_phone,
      rts.ts_created,
      NULL AS ts_updated
    FROM
      reservations_ts_ended AS rts
    LEFT JOIN
      reservations AS r
        ON rts.id_task = r.id_task
        AND rts.id_task_queue = r.id_task_queue
        and r.ts_created >= rts.ts_created 
        AND r.ts_created < COALESCE(rts.ts_created_ended, CURRENT_TIMESTAMP())
    LEFT JOIN 
      customer_identification AS ci
        ON ci.formatted_phone = rts.customer_phone
    WHERE
      task_queue_name <> previous_task_queue_name
  )
  SELECT
    crd.id_external_service,
    crd.id_channel,
    crd.id_task_queue,
    crd.id_reservation,
    crd.id_agent,
    crd.id_event,
    crd.id_call,
    crd.id_user,
    crd.task_queue_name,
    crd.channel_name,
    crd.agent_email,
    crd.agent_location,
    crd.customer_phone,
    call.id_external_service IS NOT NULL AS is_answered,
    crd.ts_created,
    crd.ts_updated
  FROM
    call_received_demand AS crd
  LEFT JOIN 
    datalake_customer_support.call
      ON crd.id_external_service = call.id_external_service
      AND crd.id_reservation = call.id_segment
),

chat AS(
  WITH task_event as (
    SELECT
      te.id_task_external AS id_external_service,
      GET_JSON_OBJECT(te.event_payload,'$.TaskChannelSid') AS id_channel,
      GET_JSON_OBJECT(te.event_payload,'$.TaskQueueSid') AS id_task_queue,
      GET_JSON_OBJECT(te.event_payload,'$.ReservationSid') AS id_reservation,
      GET_JSON_OBJECT(te.event_payload,'$.WorkerSid') AS id_agent,
      GET_JSON_OBJECT(te.event_payload,'$.Sid') AS id_event,
      te.event_type AS type,
      GET_JSON_OBJECT(te.event_payload,'$.TaskQueueName') AS task_queue_name,
      GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.email') AS agent_email,
      GET_JSON_OBJECT(GET_JSON_OBJECT(event_payload,'$.WorkerAttributes'), '$.location') AS agent_location,
      GET_JSON_OBJECT(GET_JSON_OBJECT(te.event_payload,'$.TaskAttributes'),'$.originalNumber') AS customer_phone,
      GET_JSON_OBJECT(GET_JSON_OBJECT(te.event_payload,'$.TaskAttributes'), '$.conversations') AS conversations,
      te.ts_created,
      te.ts_updated
    FROM
      datalake_quinto_messenger_clean.task_event AS te
  ),
  created_events as (
    SELECT
      id_external_service,
      id_reservation,
      agent_location,
      customer_phone,
      ts_created
    FROM
      task_event
    WHERE
      type = 'reservation.created'
  ),
  chat_received_demand AS (
    SELECT
      ce.id_external_service,
      te.id_channel,
      te.id_task_queue,
      ce.id_reservation,
      te.id_agent,
      te.id_event,
      te.conversations,
      te.task_queue_name,
      IFNULL(LEAD(te.task_queue_name) OVER (PARTITION BY te.id_external_service ORDER BY te.ts_created), '-') AS next_task_queue_name,
      te.agent_email,
      ce.agent_location,
      ce.customer_phone,
      ce.ts_created,
      te.ts_updated
    FROM
      created_events AS ce
    JOIN
      task_event AS te
        ON ce.id_external_service = te.id_external_service
    WHERE
      GET_JSON_OBJECT(te.conversations, '$.conversation_attribute_2') = true
  ),
  customer_identification AS (
    SELECT
      customer_contact,
      MAX(id_user) AS id_user
    FROM
      datalake_ebdb_customer_contact_identification.customer_contact_identification
    WHERE
      channel = 'phone'
    GROUP BY 1
  )
    SELECT
    crd.id_external_service,
    crd.id_channel,
    crd.id_task_queue,
    crd.id_reservation,
    crd.id_agent,
    crd.id_event,
    NULL AS id_call,
    ci.id_user,
    crd.task_queue_name,
    'chat' AS channel_name,
    crd.agent_email,
    crd.agent_location,
    crd.customer_phone,
    GET_JSON_OBJECT(crd.conversations, '$.conversation_measure_1') IS NOT NULL AS is_answered,
    crd.ts_created,
    crd.ts_updated
  FROM
    chat_received_demand AS crd
  LEFT JOIN 
    customer_identification AS ci
      ON ci.customer_contact = crd.customer_phone
  WHERE
    task_queue_name <> next_task_queue_name
),

email AS(
  SELECT
    id_ticket AS id_external_service,
    NULL AS id_channel,
    NULL AS id_task_queue,
    NULL AS id_reservation,
    NULL AS id_agent,
    NULL AS id_event,
    NULL AS id_call,
    id_user,
    department AS task_queue_name,
    'email' AS channel_name,
    agent_email,
    agent_company AS agent_location,
    NULL AS customer_phone,
    true AS is_answered,
    ts_ticket_started AS ts_created,
    NULL AS ts_updated
  FROM 
    datalake_customer_support.email
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