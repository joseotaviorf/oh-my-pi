WITH customer_phone AS (
  SELECT
    REGEXP_REPLACE(customer_contact, '(^\\+?55)|(\\D*)', '') AS phone_number,
    id_user
  FROM
    datalake_ebdb_customer_contact_identification.customer_contact_identification
  WHERE
    channel = 'phone'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY phone_number ORDER BY id_user DESC) = 1
),
customer_email AS (
  SELECT
    customer_contact AS email,
    id_user
  FROM
    datalake_ebdb_customer_contact_identification.customer_contact_identification
  WHERE
      channel = 'email'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY email ORDER BY id_user DESC) = 1
),
call AS (
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
  SELECT DISTINCT
    crd.id_call,
    NULL AS id_session,
    call.id_ticket AS id_ticket,
    crd.id_task,
    cp.id_user,
    crd.id_reservation,
    crd.agent_email,
    'call' AS channel,
    crd.customer_phone,
    NULL AS customer_email,
    crd.task_queue_name AS department,
    call.client_type,
    call.customer_type_tag,
    call.contact_motivation_tag,
    call.contact_theme_tag,
    call.contact_theme_detail_tag,
    call.step_tag,
    call.request_type,
    NULL AS completion_reason,
    CASE
      WHEN call.id_external_service IS NULL THEN 'ABANDONED'
      WHEN ROW_NUMBER() OVER(PARTITION BY crd.id_call ORDER BY crd.ts_created DESC) = 1 THEN 'COMPLETED'
      ELSE 'TRANSFERRED'
    END AS status,
    call.id_external_service IS NOT NULL AS is_answered,
    NULL AS ts_reservation_created,
    crd.ts_created
  FROM
    call_received_demand AS crd
  LEFT JOIN
    datalake_customer_support.call
      ON crd.id_task = call.id_external_service
      AND crd.id_reservation = call.id_segment
  LEFT JOIN
    customer_phone AS cp
      ON cp.phone_number = crd.customer_phone
),
chat AS (
  WITH current_queue AS (
    SELECT
      GET_JSON_OBJECT(event_payload,'$.TaskQueueSid') AS id_task_queue,
      GET_JSON_OBJECT(event_payload,'$.TaskQueueName') AS task_queue_name
    FROM
      datalake_quinto_messenger_clean.task_event
    QUALIFY
      ROW_NUMBER() OVER(PARTITION BY GET_JSON_OBJECT(event_payload,'$.TaskQueueSid') ORDER BY ts_created DESC) = 1
  ),
  reservation_created_events AS (
    SELECT
      id_task_external,
      FROM_UTC_TIMESTAMP(ts_created, 'America/Sao_Paulo') AS ts_reservation_created
    FROM
      datalake_quinto_messenger_clean.task_event
    WHERE
      event_type = 'reservation.accepted'
    QUALIFY
      ROW_NUMBER() OVER(PARTITION BY id_task_external ORDER BY ts_created) = 1
  ),
  task AS (
    SELECT
      id_task,
      id_channel,
      task_status,
      id_chat,
      agent_email,
      ticket_group_name,
      REGEXP_REPLACE(from_phone_number, '^\\+(?=.*)', '') AS customer_phone,
      completion_reason,
      ts_created_local AS ts_created
    FROM
      datalake_quinto_messenger.task AS t
  ),
  task_reservations AS (
    SELECT
      t.id_task,
      chn.id_source AS id_session_whats,
      c.id_session AS id_session_inapp,
      COALESCE(cq.task_queue_name, t.ticket_group_name) AS task_queue_name,
      t.agent_email,
      t.customer_phone,
      t.completion_reason,
      CASE
        WHEN t.task_status = 'canceled' THEN FALSE
        WHEN t.completion_reason = 'Task TTL Exceeded or Max assignment count exceeded' THEN FALSE
        ELSE TRUE
      END AS is_answered,
      t.ts_created AS ts_task_created,
      rce.ts_reservation_created,
      COALESCE(rce.ts_reservation_created, t.ts_created) AS ts_created
    FROM
      task AS t
    LEFT JOIN
      reservation_created_events AS rce
        ON rce.id_task_external = t.id_task
    LEFT JOIN
      current_queue AS cq
        ON cq.id_task_queue = t.ticket_group_name
    LEFT JOIN
      datalake_quinto_messenger.channel AS chn
        ON chn.id_channel = t.id_channel
    LEFT JOIN
      datalake_quinto_messenger.chat AS c
        ON c.id_chat = t.id_chat
  ),
  ticket_assignment AS (
    SELECT DISTINCT
      COALESCE(tr.id_session_whats, tr.id_session_inapp) AS id_session,
      c.id_ticket AS id_ticket,
      tr.id_task,
      cp.id_user,
      tr.agent_email,
      tr.customer_phone,
      tr.task_queue_name AS department,
      tr.completion_reason,
      c.client_type,
      c.customer_type_tag,
      c.contact_motivation_tag,
      c.contact_theme_tag,
      c.contact_theme_detail_tag,
      c.step_tag,
      c.request_type,
      tr.is_answered,
      tr.ts_reservation_created,
      tr.ts_created
    FROM
      task_reservations AS tr
    LEFT JOIN
      datalake_customer_support.chat AS c
        ON c.id_segment = tr.id_task
    LEFT JOIN
      customer_phone AS cp
        ON cp.phone_number = tr.customer_phone
  )
  SELECT DISTINCT
    NULL AS id_call,
    id_session,
    id_ticket,
    id_task,
    id_user,
    NULL AS id_reservation,
    agent_email,
    'chat' AS channel,
    customer_phone,
    NULL AS customer_email,
    department,
    client_type,
    customer_type_tag,
    contact_motivation_tag,
    contact_theme_tag,
    contact_theme_detail_tag,
    step_tag,
    request_type,
    completion_reason,
    CASE
      WHEN completion_reason = 'task idled' THEN 'IDLED'
      WHEN completion_reason = 'session expired' THEN 'EXPIRED'
      WHEN ROW_NUMBER() OVER(PARTITION BY id_session ORDER BY ts_created DESC) = 1 THEN 'COMPLETED'
      ELSE 'TRANSFERRED'
    END AS status,
    is_answered,
    ts_reservation_created,
    ts_created
  FROM
    ticket_assignment
),
email AS (
  SELECT DISTINCT
    NULL AS id_call,
    NULL AS id_session,
    id_ticket,
    NULL AS id_task,
    ce.id_user,
    NULL AS id_reservation,
    agent_email,
    'email' AS channel,
    NULL AS customer_phone,
    ce.email AS customer_email,
    department,
    client_type,
    customer_type_tag,
    contact_motivation_tag,
    contact_theme_tag,
    contact_theme_detail_tag,
    step_tag,
    request_type,
    NULL AS completion_reason,
    CASE
      WHEN ts_ticket_ended IS NOT NULL THEN 'COMPLETED'
      ELSE 'IN PROGRESS'
    END AS status,
    TRUE AS is_answered,
    NULL AS ts_reservation_created,
    ts_ticket_started AS ts_created
  FROM
    datalake_customer_support.email AS e
  LEFT JOIN
    datalake_zendesk_tickets_clean.users AS usr
      ON usr.id_user = e.id_requester
  LEFT JOIN
    customer_email AS ce
      ON ce.email = usr.email
  WHERE
    front_or_back = 'front'
),
received_demand AS (
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
),
average_reply_time AS (
  SELECT
    id_task,
    msg_sender AS agent_email,
    AVG(reply_time) AS average_reply_time
  FROM
    datalake_quinto_messenger.message
  WHERE
    msg_sender LIKE "%@%.com%"
  GROUP BY 1, 2
)
SELECT
  rd.id_call,
  rd.id_session,
  rd.id_ticket,
  rd.id_task,
  rd.id_user,
  rd.id_reservation,
  rd.agent_email,
  rd.channel,
  rd.customer_phone,
  rd.customer_email,
  rd.department,
  rd.client_type,
  rd.customer_type_tag,
  rd.contact_motivation_tag,
  rd.contact_theme_tag,
  rd.contact_theme_detail_tag,
  rd.step_tag,
  rd.request_type,
  rd.completion_reason,
  rd.status,
  art.average_reply_time,
  rd.is_answered,
  rd.ts_reservation_created,
  rd.ts_created
FROM
  received_demand AS rd
LEFT JOIN
  average_reply_time AS art
    ON art.id_task = rd.id_task
    AND art.agent_email = rd.agent_email
    AND channel = 'chat'
