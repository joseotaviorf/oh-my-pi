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
sessions AS (
  SELECT
    id AS id_session,
    user_data:["user_id"] AS id_user,
    status,
    source,
    source_identity
  FROM
    datalake_sauron_clean.session
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_session ORDER BY ts_updated DESC) = 1
),
call AS (
  WITH twilio_call_flex_events AS (
    SELECT
      id_call,
      id_task,
      id_queue AS id_task_queue,
      id_reservation,
      event_type,
      worker_email AS agent_email,
      queue_name AS task_queue_name,
      CASE
        WHEN channel_type = "call-in-app" OR direction = "outbound-api" THEN "call inapp"
        ELSE CONCAT("call ", direction)
      END AS origin,
      IFNULL(LAG(queue_name) OVER (PARTITION BY id_task ORDER BY ts_created), '-') AS previous_task_queue_name,
      CASE
        WHEN direction = "inbound"
          THEN REGEXP_REPLACE(NULLIF(REGEXP_EXTRACT(from_phone_number,'(sip:)?([0-9+]+)@?',2),''),'(^\\+?55)|(\\D*)','')
        WHEN direction = "outbound"
          THEN REGEXP_REPLACE(NULLIF(REGEXP_EXTRACT(outbound_to_phone_number,'(sip:)?([0-9+]+)@?',2),''),'(^\\+?55)|(\\D*)','')
      END AS customer_phone,
      ts_created - INTERVAL 3 HOUR AS ts_created
    FROM
      datalake_bigfone_clean.event
    WHERE
      direction IN ("inbound", "outbound-api")
      OR channel_type = "call-in-app"
  ),
  reservations_ts AS (
    SELECT
      id_call,
      id_task,
      id_task_queue,
      id_reservation,
      agent_email,
      previous_task_queue_name,
      origin,
      task_queue_name,
      customer_phone,
      ts_created
    FROM
      twilio_call_flex_events AS tcfe
    WHERE
      task_queue_name != previous_task_queue_name
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
      rts.origin,
      r.agent_email,
      rts.customer_phone,
      rts.ts_created,
      r.ts_created AS ts_reservation_created
    FROM
      reservations_ts_ended AS rts
    LEFT JOIN
      reservations AS r
        ON rts.id_task = r.id_task
        AND rts.id_task_queue = r.id_task_queue
        AND r.ts_created >= rts.ts_created
        AND r.ts_created < COALESCE(rts.ts_created_ended, CURRENT_TIMESTAMP())
    WHERE
      task_queue_name <> previous_task_queue_name
  ),
  call_sessions AS (
    SELECT DISTINCT
      crd.id_call,
      s.id_session,
      crd.id_task,
      COALESCE(s.id_user, cp.id_user) AS id_user,
      crd.id_reservation,
      crd.origin,
      crd.agent_email,
      crd.customer_phone,
      crd.task_queue_name AS department,
      crd.ts_created,
      crd.ts_reservation_created
    FROM
      call_received_demand AS crd
    LEFT JOIN
      sessions AS s
        ON s.source_identity = crd.id_call
    LEFT JOIN
      customer_phone AS cp
        ON cp.phone_number = crd.customer_phone
  ),
  call_tickets AS (
    SELECT
      id_ticket,
      id_external_service,
      id_segment,
      client_type,
      customer_type_tag,
      contact_motivation_tag,
      contact_theme_tag,
      contact_theme_detail_tag,
      step_tag,
      request_type,
      area,
      front_or_back
    FROM
      datalake_customer_support.call
    QUALIFY
      ROW_NUMBER() OVER(PARTITION BY id_ticket, id_external_service, id_segment ORDER BY ts_segment_created DESC) = 1
  )
  SELECT DISTINCT
    cs.id_call,
    cs.id_session,
    ct.id_ticket,
    cs.id_task,
    cs.id_user,
    cs.id_reservation,
    cs.agent_email,
    "call" AS channel,
    cs.origin,
    cs.customer_phone,
    NULL AS customer_email,
    cs.department,
    ct.area,
    ct.front_or_back,
    ct.client_type,
    ct.customer_type_tag,
    ct.contact_motivation_tag,
    ct.contact_theme_tag,
    ct.contact_theme_detail_tag,
    ct.step_tag,
    ct.request_type,
    NULL AS completion_reason,
    CASE
      WHEN ct.id_external_service IS NULL THEN 'ABANDONED'
      WHEN ROW_NUMBER() OVER(PARTITION BY cs.id_call ORDER BY cs.ts_created DESC) = 1 THEN 'COMPLETED'
      ELSE 'TRANSFERRED'
    END AS status,
    cfr.is_answered,
    NULL AS is_per_team_task,
    cs.ts_reservation_created,
    cs.ts_created AS ts_task_created,
    cs.ts_created
  FROM
    call_sessions AS cs
  LEFT JOIN
    call_tickets AS ct
      ON cs.id_task = ct.id_external_service
      AND cs.id_reservation = ct.id_segment
  LEFT JOIN
    datalake_bigfone.reservations AS cfr
      ON cs.id_reservation = cfr.id_reservation
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
  per_team_attr AS (
    SELECT
      id_task,
      GET_JSON_OBJECT(task_attributes,'$.conversations.conversation_attribute_2') AS is_per_team_task
    FROM
      datalake_quinto_messenger_clean.task
    QUALIFY
      ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_updated DESC) = 1
  ),
  reservation_created_events AS (
    SELECT
      id_task AS id_task_external,
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
      pta.is_per_team_task,
      rce.ts_reservation_created,
      COALESCE(rce.ts_reservation_created, t.ts_created) AS ts_created,
      t.ts_created AS ts_task_created
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
    LEFT JOIN
      per_team_attr AS pta
        ON pta.id_task = t.id_task
  ),
  ticket_assignment AS (
    SELECT DISTINCT
      COALESCE(tr.id_session_whats, tr.id_session_inapp) AS id_session,
      c.id_ticket AS id_ticket,
      tr.id_task,
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
      c.area,
      c.front_or_back,
      tr.is_answered,
      tr.is_per_team_task,
      tr.ts_reservation_created,
      tr.ts_task_created,
      tr.ts_created
    FROM
      task_reservations AS tr
    LEFT JOIN
      datalake_customer_support.chat AS c
        ON c.id_segment = tr.id_task
  )
  SELECT DISTINCT
    NULL AS id_call,
    ta.id_session,
    id_ticket,
    id_task,
    COALESCE(s.id_user, cp.id_user) AS id_user,
    NULL AS id_reservation,
    agent_email,
    'chat' AS channel,
    NULL AS origin,
    customer_phone,
    NULL AS customer_email,
    department,
    area,
    front_or_back,
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
      WHEN completion_reason = 'task completed' THEN 'COMPLETED'
      WHEN completion_reason = 'task transferred' THEN 'TRANSFERRED'
      WHEN ROW_NUMBER() OVER(PARTITION BY ta.id_session ORDER BY ta.ts_created DESC) = 1 THEN 'COMPLETED'
      ELSE 'TRANSFERRED'
    END AS status,
    is_answered,
    is_per_team_task,
    ts_reservation_created,
    ts_task_created,
    ts_created
  FROM
    ticket_assignment AS ta
  LEFT JOIN
    sessions AS s
      ON s.id_session = ta.id_session
  LEFT JOIN
    customer_phone AS cp
      ON cp.phone_number = ta.customer_phone
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
    NULL AS origin,
    NULL AS customer_phone,
    ce.email AS customer_email,
    department,
    area,
    front_or_back,
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
    NULL AS is_per_team_task,
    NULL AS ts_reservation_created,
    NULL AS ts_task_created,
    ts_ticket_started AS ts_created
  FROM
    datalake_customer_support.email AS e
  LEFT JOIN
    datalake_support_users.zendesk_users AS usr
      ON usr.id_user_zendesk = e.id_requester
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
),
time_metrics AS (
  SELECT
    id_conversation,
    id_segment AS id_task,
    id_reservation,
    total_queue_time,
    total_talk_time,
    total_wrap_up_time,
    total_handling_time,
    total_waiting_time,
    first_reply_time
  FROM
    datalake_twilio_flex_insights_clean.conversation_time_metrics
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_segment ORDER BY dt_created DESC) = 1
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
  rd.origin,
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
  COALESCE(rd.area, dc.area) AS area,
  LOWER(COALESCE(rd.front_or_back, dc.front_or_back)) AS front_or_back,
  art.average_reply_time,
  tm.total_talk_time,
  tm.total_queue_time,
  tm.total_wrap_up_time,
  tm.total_waiting_time,
  tm.first_reply_time,
  tm.total_handling_time,
  COALESCE(rd.is_answered, FALSE) AS is_answered,
  rd.is_per_team_task,
  rd.ts_reservation_created,
  rd.ts_task_created,
  rd.ts_created
FROM
  received_demand AS rd
LEFT JOIN
  average_reply_time AS art
    ON art.id_task = rd.id_task
    AND art.agent_email = rd.agent_email
    AND channel = 'chat'
LEFT JOIN
  time_metrics AS tm
    ON tm.id_task = rd.id_task
    OR tm.id_reservation = rd.id_reservation
LEFT JOIN
  datalake_gsheets_clean.department_control AS dc
    ON dc.department = rd.department
