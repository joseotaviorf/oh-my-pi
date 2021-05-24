WITH tasks AS (
  WITH last_updated_reservations AS (
    SELECT
        id_reservation,
        MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated
    FROM
        datalake_bigfone_twilio.call_flex_reservations
    GROUP BY 1
  ),
  twilio_timestamp AS (
    SELECT
        id_reservation,
        ts_created_local AS ts_twilio_created_local,
        ts_created_utc AS ts_twilio_created_utc
    FROM
        datalake_bigfone_twilio.call_flex_events
    WHERE
        event_type = 'reservation.accepted'
    GROUP BY 1,2,3
  ),
  task_closed AS (
    SELECT
        GET_JSON_OBJECT(metadata,'$.event_data.ReservationSid') AS id_reservation,
        FROM_UTC_TIMESTAMP(TO_TIMESTAMP(event_timestamp, 'yyyy-MM-dd HH:mm:ss'), 'Brazil/East') AS ts_closed
    FROM
        datalake_bigfone_clean.event
    WHERE
        event IN ('reservation.completed', 'reservation.timeout', 'reservation.canceled', 'reservation.rejected')
    GROUP BY 1,2
  ),
  agent_info AS (
    SELECT
      id_task,
      id_reservation,
      cfe.agent_email,
      GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.location') AS agent_company,
      ac.agent_name,
      ac.manager AS agent_manager,
      GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.routing.skills') AS agent_skills
    FROM
      datalake_bigfone_twilio.call_flex_events cfe
    JOIN
      datalake_gsheets_clean.agents_control ac
        ON cfe.agent_email = ac.email
    GROUP BY 1,2,3,4,5,6,7
  )
  SELECT
    r.id_reservation,
    COALESCE(id_call,r.id_task) AS sk_call,
    id_call,
    r.id_task,
    id_agent,
    id_queue,
    agent_email,
    agent_manager,
    agent_company,
    agent_name,
    agent_skills,
    queue_name,
    seconds_duration,
    seconds_wait_time,
    seconds_talk_time,
    is_answered,
    is_timeout,
    is_rejected,
    lur.dt_last_updated AS dt_updated,
    ts_created,
    ts_ended,
    tt.ts_twilio_created_local,
    tt.ts_twilio_created_utc,
    tc.ts_closed
  FROM
    datalake_bigfone_twilio.call_flex_reservations r
  JOIN
    agent_info ae
      ON ae.id_task = r.id_task
      AND ae.id_reservation = r.id_reservation
  INNER JOIN
    last_updated_reservations lur
        ON lur.id_reservation = r.id_reservation
        AND lur.dt_last_updated = DATE(CONCAT(r.year, '-', r.month, '-', r.day))
  LEFT JOIN
    twilio_timestamp tt
        ON tt.id_reservation = r.id_reservation
  LEFT JOIN
    task_closed tc
        ON tc.id_reservation = r.id_reservation
),
call AS (
  WITH ivr_events AS (
      SELECT
          id_call,
          from_number,
          to_number,
          customer_phone,
          UNIX_TIMESTAMP(MAX(ts_created_local)) - UNIX_TIMESTAMP(MIN(ts_created_local)) AS initial_ivr_time,
          MIN(id_task) AS id_task, -- workaround to filter 1 instance with duplicity
          MIN(ts_created_local) AS ts_first_event,
          MAX(ts_created_local) AS ts_last_event,
          MIN(ts_created_local_unix) AS ts_first_event_local_unix,
          MAX(ts_created_local_unix) AS ts_last_event_local_unix
      FROM
          datalake_bigfone_twilio.call_ivr_events
      GROUP BY 1,2,3,4
  ),
  call_events AS (
      SELECT
          id_task,
          id_call,
          id_conversation,
          customer_phone,
          from_number,
          to_number,
          direction,
          is_scheduled,
          scheduling_source,
          MIN(ts_created_local) AS ts_first_event,
          MAX(ts_created_local) AS ts_last_event,
          MIN(ts_created_local_unix) AS ts_first_event_local_unix,
          MAX(ts_created_local_unix) AS ts_last_event_local_unix,
          MAX(ts_wrapup_event_local_unix) AS ts_wrapup_event_local_unix
      FROM
          datalake_bigfone_twilio.call_flex_events
      WHERE
          event_type != 'task.updated'
      GROUP BY 1,2,3,4,5,6,7,8,9
  ),
  csat_events AS (
      SELECT
          id_call,
          id_task,
          MAX(csat_1) AS csat_1,
          MAX(csat_2) AS csat_2,
          MIN(ts_created_local) AS ts_csat
      FROM
          datalake_bigfone_twilio.call_ivr_events
      WHERE
          COALESCE(csat_1, csat_2) IS NOT NULL
      GROUP BY 1,2
  ),
  call_metrics AS (
      SELECT
          id_task,
          id_call,
          COUNT(DISTINCT queue_name) AS number_of_departments,
          COUNT(DISTINCT id_reservation) AS number_of_tasks,
          COUNT(id_reservation) AS reservations,
          SUM(CAST(is_answered AS SMALLINT)) AS reservations_accepted,
          SUM(seconds_wait_time) AS wait_time_flex,
          SUM(seconds_talk_time) AS talk_time,
          MIN(ts_created) AS ts_first_reservation,
          MAX(ts_created) AS ts_last_reservation
      FROM
          datalake_bigfone_twilio.call_flex_reservations
      GROUP BY 1,2
  )
  SELECT
      COALESCE(ie.id_call, fe.id_call) AS id_call,
      COALESCE(ie.id_call, fe.id_call, fe.id_conversation, fe.id_task) AS sk_call,
      fe.id_conversation,
      fe.id_task,
      COALESCE(ie.from_number,fe.from_number) AS from_phone_number,
      COALESCE(ie.to_number,fe.to_number) AS to_phone_number,
      ie.initial_ivr_time AS seconds_ivr_time,
      fe.direction,
      fe.scheduling_source,
      COALESCE(cm.number_of_tasks,0) AS number_of_tasks,
      COALESCE(cm.number_of_departments,0) AS number_of_departments,
      cm.reservations IS NULL AS has_ended_in_ura,
      cm.reservations_accepted > 0 AS is_answered,
      cm.reservations > 1 AS is_transfered,
      cm.wait_time_flex AS seconds_total_wait_time,
      cm.talk_time AS seconds_total_talk_time,
      ce.csat_2 IS NOT NULL AS is_csat_answered,
      ce.csat_1 = 1 AS is_solved,
      ce.csat_2 AS csat_rating,
      GREATEST(ie.ts_last_event_local_unix,fe.ts_last_event_local_unix) - COALESCE(ie.ts_first_event_local_unix,fe.ts_first_event_local_unix) AS seconds_duration,
      COALESCE(ie.ts_first_event,fe.ts_first_event) AS ts_started,
      ce.ts_csat AS ts_csat_answered,
      GREATEST(ie.ts_last_event,fe.ts_last_event) AS ts_ended,
      cfe.ts_created_local AS ts_created
  FROM
      ivr_events ie
  FULL JOIN
      call_events fe
          ON fe.id_call = ie.id_call
  LEFT JOIN 
      datalake_bigfone_twilio.call_flex_events cfe
          ON fe.id_task = cfe.id_task
  LEFT JOIN
      csat_events ce
          ON ce.id_call = ie.id_call
  LEFT JOIN
      call_metrics cm
          ON cm.id_task = fe.id_task
),
zendesk_aditional_ticket_info AS (
  SELECT DISTINCT 
    tf.id_ticket,
    ftm.id_call,
    tf.tags,
    tf.description,
    tf.status,
    tf.custom_fields,
    tf.group_name AS zendesk_ticket_department,
    ftm.minutes_first_resolution_calendar AS minutes_first_resolution_time_calendar,
    ftm.minutes_first_resolution_business AS minutes_first_resolution_time_business,
    tf.request_type,
    tf.client_type,
    tf.customer_type_tag,
    tf.contact_motivation_tag,
    tf.contact_theme_tag
  FROM
    datalake_zendesk_ticket_funnels.ticket_funnel tf
  JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics ftm
      ON tf.id_ticket = ftm.id_ticket
  WHERE
    ftm.id_call IS NOT NULL
),
back_tickets AS (
  SELECT 
    REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})',1) AS front_task,
    zd.id_ticket AS back_ticket,
    zd.status,
    zd2.id_ticket AS front_ticket
  FROM
    zendesk_aditional_ticket_info zd
  JOIN
    call
      ON call.id_task = REGEXP_EXTRACT(description, '(WT[a-z0-9]{{20,40}})',1)
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = zd.zendesk_ticket_department 
  JOIN  
    zendesk_aditional_ticket_info zd2
      ON zd2.id_call = call.sk_call
  WHERE 
    (zd.tags LIKE '%tarefa_atendimento_escalado%' OR LOWER(dc.front_or_back) = 'back')
    AND (zd.tags NOT LIKE '%bot_end_conversation%' AND zd.tags NOT LIKE '%closed_by_merge%')
    AND REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})',1) != '' 
  GROUP BY 1,2,3,4
),
first_and_last_task AS (
  SELECT
    id_ticket,
    FIRST(t.id_reservation) OVER (PARTITION BY id_ticket ORDER BY t.ts_twilio_created_local ASC) AS first_task,
    LAST(t.id_reservation) OVER (PARTITION BY id_ticket ORDER BY t.ts_twilio_created_local ASC) AS last_task
  FROM 
    tasks t
  JOIN 
    call c
      ON t.sk_call = c.sk_call
  JOIN 
    zendesk_aditional_ticket_info zd 
      ON zd.id_call IS NOT NULL
      AND zd.id_call = c.id_call
)
SELECT
  DISTINCT zd.id_ticket,
  t.id_task,
  t.id_reservation,
  t.id_call,
  c.id_conversation,
  t.id_agent,
  t.id_queue,
  t.agent_email,
  t.agent_manager,
  t.agent_company,
  t.agent_name,
  t.agent_skills,
  t.queue_name AS department,
  FIRST(t.queue_name) OVER (PARTITION BY c.id_task ORDER BY c.ts_created) AS first_department,
  LAST(t.queue_name) OVER (PARTITION BY c.id_task ORDER BY c.ts_created) AS last_department,
  CASE
      WHEN seconds_total_wait_time <= 60 AND t.is_answered THEN TRUE
      WHEN seconds_total_wait_time > 60 AND t.is_answered THEN FALSE
      ELSE NULL
  END AS sla_achieved,
  t.seconds_duration/60.0 AS task_minutes_duration,
  t.seconds_wait_time/60.0 AS task_minutes_wait_time,
  c.seconds_duration/60.0 AS minutes_full_resolution_time_calendar,
  c.number_of_departments,
  c.number_of_tasks,
  c.direction,
  zd.minutes_first_resolution_time_calendar,
  zd.minutes_first_resolution_time_business,
  zd.request_type,
  zd.client_type,
  zd.customer_type_tag,
  zd.contact_motivation_tag,
  zd.contact_theme_tag,
  zd.tags,
  zd.status,
  zd.custom_fields,
  last_task.id_ticket IS NOT NULL AS is_last_task,
  first_task.id_ticket IS NOT NULL AS is_first_task,
  bt.front_ticket IS NOT NULL AS has_back_tickets,
  zd.tags LIKE '%bot_end_conversation%' AS is_bot, 
  zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  c.has_ended_in_ura = FALSE AND t.is_answered = TRUE AS is_answered,
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  CASE
    WHEN bt.status IN ('open','pending','new','hold') THEN TRUE
    WHEN bt.status IN ('closed','deleted','solved') THEN FALSE
  END AS is_open_back_ticket,
  CASE
    WHEN c.is_transfered = TRUE THEN TRUE
    ELSE FALSE
  END AS has_transfers,
  bt.back_ticket,
  c.is_csat_answered,
  c.is_solved,
  c.csat_rating,
  c.ts_csat_answered,
  t.ts_twilio_created_local AS ts_task_created,
  t.ts_closed AS ts_task_closed,
  c.ts_started AS ts_ticket_started,
  c.ts_ended AS ts_ticket_ended
FROM 
  tasks t
JOIN 
  call c
    ON t.sk_call = c.sk_call
JOIN 
  zendesk_aditional_ticket_info zd 
    ON zd.id_call IS NOT NULL
    AND zd.id_call = c.id_call
LEFT JOIN
  first_and_last_task last_task
    ON last_task.id_ticket = zd.id_ticket
    AND last_task.last_task = t.id_reservation
LEFT JOIN
  first_and_last_task first_task
    ON first_task.id_ticket = zd.id_ticket
    AND first_task.first_task = t.id_reservation
JOIN
  datalake_gsheets_clean.department_control dc
    ON dc.department = t.queue_name 
    AND LOWER(dc.front_or_back) <> 'back'
LEFT JOIN
  back_tickets bt
    ON bt.front_ticket = zd.id_ticket
WHERE
  zd.tags NOT LIKE '%tarefa_atendimento_escalado%'
