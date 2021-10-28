WITH teravoz_events AS (
  WITH queues AS (
    SELECT 
      bq.id AS id_event,
      bq.queue AS id_queue,
      tq.name AS queue_name
    FROM
      datalake_bigfone_clean.queued bq
    JOIN
      datalake_teravoz_clean.queues tq
        ON tq.number = bq.queue
    WHERE
      bq.queue IS NOT NULL
    GROUP BY 1,2,3
  ),
  calls_queues AS (
    SELECT 
      bt.id_event,
      bt.id_call,
      q.id_queue,
      q.queue_name,
      bt.provider,
      bt.seconds_talk_duration,
      bt.direction,
      FIRST_VALUE(q.queue_name) OVER (PARTITION BY bt.id_call ORDER BY q.queue_name IS NULL, bt.ts_created ASC) AS first_queue,
      FIRST_VALUE(q.queue_name) OVER (PARTITION BY bt.id_call ORDER BY q.queue_name IS NULL, bt.ts_created DESC) AS last_queue
      bt.ts_created,
      bt.ts_created_local,
      bt.year,
      bt.month,
      bt.day
    FROM
      datalake_bigfone_events.events_bigfone_teravoz bt
    LEFT JOIN
      queues q
        ON q.id_event = bt.id_event
  ),
  timestamp_call AS (
    SELECT 
      cq.id_call,
      MAX(DATE(CONCAT(cq.year, '-', cq.month, '-', cq.day))) AS ts_call_last_updated,
      MIN(cq.ts_created) AS ts_call_created,
      MAX(cq.ts_created) AS ts_call_closed
    FROM
      calls_queues cq
    GROUP BY 1
  ),
  call_time_metrics AS (
    SELECT
      id AS id_call,
      SUM(seconds_talk_duration) AS seconds_call_talk_duration
    FROM
      datalake_teravoz_clean.calls
    GROUP BY 1
  )
  SELECT
    cq.id_event,
    cq.id_call,
    cq.id_queue,
    cq.queue_name,
    cq.provider,
    cq.direction,
    cq.first_queue,
    cq.last_queue,
    cq.seconds_talk_duration,
    ttm.seconds_call_talk_duration,
    tc.ts_call_last_updated,
    cq.ts_created,
    tc.ts_call_created,
    tc.ts_call_closed
  FROM
    calls_queues cq
  LEFT JOIN 
    call_time_metrics ttm
      ON ttm.id_call = cq.id_call
  LEFT JOIN
    timestamp_call tc
      ON tc.id_call = cq.id_call
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
    tf.step_tag,
    tf.customer_type_tag,
    tf.contact_motivation_tag,
    tf.contact_theme_tag,
    tf.contact_theme_detail_tag,
    ftm.ts_created_local AS ts_created,
    ftm.ts_solved_local AS ts_solved
  FROM
    datalake_zendesk_ticket_funnels.ticket_funnel tf
  JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics ftm
      ON tf.id_ticket = ftm.id_ticket
)
SELECT 
  COALESCE(zd.id_ticket, te.id_call) AS id_ticket,
  zd.id_user,
  zd.id_contract,
  t.id_assignee AS id_agent,
  te.id_call AS id_segment,
  te.id_call,
  te.id_queue,
  te.queue_name AS department,
  zd.zendesk_ticket_department AS zendesk_department,
  te.first_queue AS first_department,
  te.last_queue AS last_department,
  ac.agent_name,
  ac.agent_company,
  ac.manager AS agent_manager,
  ac.email AS agent_email,
  te.provider,
  te.direction,
  CAST(te.seconds_call_talk_duration AS FLOAT)/60.0 AS total_minutes_talk_time,
  CAST(te.seconds_talk_duration AS FLOAT)/60.0 AS segment_minutes_talk_time,
  zd.minutes_first_resolution_time_calendar,
  zd.minutes_first_resolution_time_business,
  zd.request_type,
  zd.client_type,
  zd.step_tag,
  zd.customer_type_tag,
  zd.contact_motivation_tag,
  zd.contact_theme_tag,
  zd.contact_theme_detail_tag,
  zd.tags,
  zd.status,
  zd.custom_fields,
  CASE 
    WHEN dc.front_or_back = 'Front' THEN 'front'
    WHEN dc.front_or_back = 'Back' OR zd.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
    ELSE 'undefined'
  END AS front_or_back,
  zd.tags LIKE '%bot_end_conversation%' AS is_bot, 
  zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  te.ts_call_last_updated AS ts_ticket_last_updated,
  te.ts_created AS ts_segment_created,
  te.ts_call_created AS ts_ticket_started,
  te.ts_call_closed AS ts_ticket_ended
FROM 
  teravoz_events te
LEFT JOIN
  zendesk_aditional_ticket_info zd
    ON zd.id_call = te.id_call
LEFT JOIN
  datalake_gsheets_clean.department_control dc
    ON dc.department = te.queue_name 
LEFT JOIN
  datalake_zendesk_tickets_clean.tickets t
    ON t.id_ticket = zd.id_ticket
LEFT JOIN
  datalake_gsheets_clean.agents_control ac
    ON t.id_assignee = ac.id_assignee