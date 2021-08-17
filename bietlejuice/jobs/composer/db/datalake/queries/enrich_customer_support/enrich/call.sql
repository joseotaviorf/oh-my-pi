/*
In order to run these queries directly from databricks notebook you must replace double 
brackets (`{{` `}}`) for single ones.
*/
WITH segment AS (
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
        MIN(ts_created_local) AS ts_twilio_created_local,
        MIN(ts_created_utc) AS ts_twilio_created_utc,
        MAX(ts_created_local) AS ts_twilio_closed_local,
        MAX(ts_created_utc) AS ts_twilio_closed_utc
    FROM
        datalake_bigfone_twilio.call_flex_events
    WHERE
        event_type LIKE 'reservation.%'
    GROUP BY 1
  ),
  agent_info AS (
    SELECT
      id_task,
      id_reservation,
      MAX(cfe.agent_email) AS agent_email,
      MAX(GET_JSON_OBJECT(metadata, '$.event_data.WorkerAttributes.location')) AS agent_company,
      MAX(ac.agent_name) AS agent_name,
      MAX(ac.manager) AS agent_manager
    FROM
      datalake_bigfone_twilio.call_flex_events cfe
    LEFT JOIN
      datalake_gsheets_clean.agents_control ac
        ON cfe.agent_email = ac.email
    WHERE
      id_reservation IS NOT NULL
    GROUP BY 1,2
  ),
  transfer_reason AS (
    SELECT DISTINCT
      id_reviewed AS id_reservation,
      rating_selected[0] AS transference_reason
    FROM 
      datalake_insider_clean.review r
    JOIN
      datalake_insider_clean.review_feature rf
        ON r.id = rf.id
    JOIN
      datalake_insider_clean.feature f
        ON rf.id_feature = f.id
    WHERE
      f.name = 'ticket_transfer_reason'
      AND r.type = 'ticket_transfer'
      AND id_reviewed like 'WR%'
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
    queue_name,
    LAG(queue_name,1) OVER (PARTITION BY COALESCE(id_call,r.id_task) ORDER BY ts_twilio_created_local) AS transferred_from_dept,
    LEAD(queue_name,1) OVER (PARTITION BY COALESCE(id_call,r.id_task) ORDER BY ts_twilio_created_local) AS transferred_to_dept,
    CASE
        WHEN 
          LEAD(queue_name,1) OVER (PARTITION BY COALESCE(id_call,r.id_task) ORDER BY ts_twilio_created_local) = queue_name 
          AND LEAD(id_queue,1) OVER (PARTITION BY COALESCE(id_call,r.id_task) ORDER BY ts_twilio_created_local) = id_queue 
          THEN 'internal-same-agent'
        WHEN 
          LEAD(queue_name,1) OVER (PARTITION BY COALESCE(id_call,r.id_task) ORDER BY ts_twilio_created_local) = queue_name 
          AND LEAD(id_queue,1) OVER (PARTITION BY COALESCE(id_call,r.id_task) ORDER BY ts_twilio_created_local) != id_queue 
          THEN 'internal-other-agent'
        WHEN LEAD(queue_name,1) OVER (PARTITION BY COALESCE(id_call,r.id_task) ORDER BY ts_twilio_created_local) != queue_name THEN 'external'
    END AS transference_type,
    tr.transference_reason,
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
    tt.ts_twilio_closed_local,
    tt.ts_twilio_closed_utc
  FROM
    datalake_bigfone_twilio.call_flex_reservations r
  JOIN
    last_updated_reservations lur
        ON lur.id_reservation = r.id_reservation
        AND lur.dt_last_updated = DATE(CONCAT(r.year, '-', r.month, '-', r.day))
  JOIN
    agent_info ae
      ON ae.id_task = r.id_task
      AND ae.id_reservation = r.id_reservation
  LEFT JOIN
    twilio_timestamp tt
      ON tt.id_reservation = r.id_reservation
  LEFT JOIN
    transfer_reason tr
      ON tr.id_reservation = r.id_reservation
  WHERE
    is_answered = TRUE
),
conversation AS (
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
          AND (
            GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.scheduled') IS NULL
            OR GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.scheduled') <> 'true'
            OR (
                  GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.scheduled') = 'true' 
                  AND GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.conversations.conversation_attribute_1') = 2
            )
          )
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
          SUM(CAST(is_answered AS SMALLINT)) AS reservations_accepted,
          SUM(seconds_wait_time) AS wait_time_flex,
          SUM(seconds_talk_time) AS talk_time,
          MIN(ts_created) AS ts_first_reservation,
          MAX(ts_created) AS ts_last_reservation
      FROM
          datalake_bigfone_twilio.call_flex_reservations
      WHERE
          is_answered = TRUE
      GROUP BY 1,2
  )
  SELECT
      COALESCE(ie.id_call, fe.id_call) AS id_call,
      COALESCE(ie.id_call, fe.id_call, fe.id_conversation, fe.id_task) AS sk_call,
      fe.id_conversation,
      COALESCE(fe.id_task, ie.id_task) AS id_task,
      COALESCE(ie.from_number,fe.from_number) AS from_phone_number,
      COALESCE(ie.to_number,fe.to_number) AS to_phone_number,
      ie.initial_ivr_time AS seconds_ivr_time,
      fe.direction,
      fe.scheduling_source,
      COALESCE(cm.number_of_tasks,0) AS number_of_tasks,
      COALESCE(cm.number_of_departments,0) AS number_of_departments,
      cm.number_of_tasks IS NULL OR cm.number_of_tasks = 0 AS has_ended_in_ura,
      cm.reservations_accepted > 0 AS is_answered,
      cm.number_of_tasks > 1 AS is_transfered,
      cm.wait_time_flex AS seconds_total_wait_time,
      cm.talk_time AS seconds_total_talk_time,
      COALESCE(CAST(ce.csat_2 AS string), CAST(ce.csat_1 AS string)) IS NOT NULL AS is_csat_answered,
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
zendesk_tickets_unique AS (
  --this CTE fix the error of multiple tickets openned for a single call
  SELECT
    tfm.id_call,
    MAX(tfm.id_ticket) AS id_ticket
  FROM
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
  WHERE
    id_call IS NOT NULL
  GROUP BY 1
),
zendesk_aditional_ticket_info AS (
  SELECT DISTINCT 
    tf.id_ticket,
    ftm.id_call,
    ftm.id_user,
    ftm.id_contract,
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
    tf.contact_theme_tag,
    ftm.ts_solved_local AS ts_solved
  FROM
    datalake_zendesk_ticket_funnels.ticket_funnel tf
  JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics ftm
      ON tf.id_ticket = ftm.id_ticket
),
back_tickets AS (
  SELECT 
    COALESCE(
      NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),
      REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1)
    ) AS front_task,
    zd.id_ticket AS back_ticket,
    zd.status,
    zd2.id_ticket AS front_ticket,
    zd.ts_solved
  FROM
    zendesk_aditional_ticket_info zd
  JOIN
    conversation c
      ON c.id_task = COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1))
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = zd.zendesk_ticket_department 
  JOIN  
    zendesk_aditional_ticket_info zd2
      ON zd2.id_call = c.sk_call
  WHERE 
    (zd.tags LIKE '%tarefa_atendimento_escalado%' OR LOWER(dc.front_or_back) = 'back')
    AND (zd.tags NOT LIKE '%bot_end_conversation%' AND zd.tags NOT LIKE '%closed_by_merge%')
    AND COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1)) != '' 
  GROUP BY 1,2,3,4,5
),
last_back_ticket_timestamp AS (
  SELECT
    front_ticket,
    CONCAT_WS(',' , COLLECT_SET(back_ticket)) AS back_ticket_list,
    SUM(CAST(status IN ('closed','deleted','solved') AS SMALLINT))/CAST(COUNT(DISTINCT back_ticket) AS FLOAT) != 1 AS is_open_back_ticket,
    MAX(ts_solved) AS ts_last_solved
  FROM
    back_tickets
  GROUP BY 1
),
last_back_ticket AS (
  SELECT
    bt.*,
    lt.is_open_back_ticket,
    lt.back_ticket_list
  FROM
    back_tickets bt
  JOIN
    last_back_ticket_timestamp lt
      ON lt.front_ticket = bt.front_ticket
      AND lt.ts_last_solved = bt.ts_solved
)
SELECT DISTINCT 
  zd.id_ticket,
  c.id_task AS id_external_service,
  t.id_reservation AS id_segment,
  c.id_call,
  c.sk_call,
  t.id_agent,
  FIRST(t.id_agent) OVER (PARTITION BY zd.id_ticket ORDER BY t.ts_twilio_created_local ASC) AS id_first_agent,
  FIRST(t.id_agent) OVER (PARTITION BY zd.id_ticket ORDER BY t.ts_twilio_created_local DESC) AS id_last_agent,
  t.id_queue,
  zd.id_user,
  zd.id_contract,
  t.agent_email,
  t.agent_manager,
  t.agent_company,
  t.agent_name,
  t.queue_name AS department,
  zd.zendesk_ticket_department AS zendesk_department,
  FIRST(t.queue_name) OVER (PARTITION BY zd.id_ticket ORDER BY t.ts_twilio_created_local ASC) AS first_department,
  FIRST(t.queue_name) OVER (PARTITION BY zd.id_ticket ORDER BY t.ts_twilio_created_local DESC) AS last_department,
  t.transferred_from_dept,
  t.transferred_to_dept,
  t.transference_type,
  t.transference_reason,
  CASE
      WHEN seconds_total_wait_time <= 60 AND t.is_answered THEN TRUE
      WHEN seconds_total_wait_time > 60 AND t.is_answered THEN FALSE
      ELSE NULL
  END AS sla_achieved,
  t.seconds_duration/60.0 AS segment_minutes_duration,
  t.seconds_wait_time/60.0 AS segment_minutes_wait_time,
  CAST(c.seconds_duration/60.0 AS DOUBLE) AS minutes_full_resolution_time_calendar,
  CAST(c.number_of_departments AS INT) AS number_of_departments,
  CAST(c.number_of_tasks AS INT) AS number_of_segments,
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
  FIRST(t.id_reservation) OVER (PARTITION BY zd.id_ticket ORDER BY t.ts_twilio_created_local DESC) = t.id_reservation AS is_last_segment,
  FIRST(t.id_reservation) OVER (PARTITION BY zd.id_ticket ORDER BY t.ts_twilio_created_local ASC) = t.id_reservation AS is_first_segment,
  bt.front_ticket IS NOT NULL AS has_back_tickets,
  zd.tags LIKE '%bot_end_conversation%' AS is_bot, 
  zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  CASE 
    WHEN dc.front_or_back = 'Back' OR zd.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
    WHEN dc.front_or_back = 'Front' OR NULLIF(dc.front_or_back, '-') IS NULL THEN 'front'
  END AS front_or_back,
  c.has_ended_in_ura = FALSE AND t.is_answered = TRUE AS is_answered,
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  bt.is_open_back_ticket,
  CASE
    WHEN c.is_transfered = TRUE THEN TRUE
    ELSE FALSE
  END AS has_transfers,
  CAST((TO_UNIX_TIMESTAMP(COALESCE(bt.ts_solved, c.ts_ended)) - TO_UNIX_TIMESTAMP(c.ts_started))/60.0 AS DOUBLE) AS frt,
  bt.back_ticket AS last_back_ticket,
  bt.back_ticket_list,
  c.is_csat_answered,
  c.is_solved,
  c.csat_rating,
  c.ts_csat_answered,
  t.ts_twilio_created_local AS ts_segment_created,
  t.ts_twilio_closed_local AS ts_segment_closed,
  c.ts_started AS ts_ticket_started,
  c.ts_ended AS ts_ticket_ended
FROM 
  conversation c
JOIN 
  zendesk_aditional_ticket_info zd 
    ON zd.id_call = c.sk_call
JOIN
  zendesk_tickets_unique ztu
    ON zd.id_ticket = ztu.id_ticket
LEFT JOIN 
  segment t
    ON t.sk_call = c.sk_call
    AND t.id_task = c.id_task
LEFT JOIN
  datalake_gsheets_clean.department_control dc
    ON dc.department = zd.zendesk_ticket_department  
LEFT JOIN
  last_back_ticket bt
    ON bt.front_ticket = zd.id_ticket
