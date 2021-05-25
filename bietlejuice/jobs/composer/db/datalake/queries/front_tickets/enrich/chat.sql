WITH quinto_messenger_tickets AS (
  WITH last_updated_task AS (
      SELECT
        id_task, 
        MAX(ts_updated) AS ts_last_updated 
      FROM datalake_quinto_messenger.task
      GROUP BY 1
  ),
  task_timestamps AS (
    SELECT
      id_task,
      MAX(ts_created_local) AS ts_task_closed,
      MIN(ts_created_local) AS ts_task_created
    FROM
      datalake_quinto_messenger.task_event
    WHERE 
      type IN ('reservation.completed', 'reservation.rejected', 'reservation.timeout', 'reservation.accepted')
    GROUP BY 1
  ),
  chat_metrics AS (
    SELECT 
      id_conversation,
      COUNT(DISTINCT t.id_task) AS number_of_tasks,
      COUNT(DISTINCT task_queue_name) AS number_of_departments,
      MAX(te.ts_created_local) AS ts_last_event,
      MIN(te.ts_created_local) AS ts_first_event
    FROM 
      datalake_quinto_messenger.task t
    JOIN 
      datalake_quinto_messenger.task_event te
        ON t.id_task = te.id_task
    GROUP BY 1
  )
  SELECT
      t.id_task,
      c.id_conversation,
      c.id_source AS id_session,
      id_agent,
      t.agent_email,
      ac.manager AS agent_manager,
      ac.agent_name,
      ac.agent_company,
      seconds_to_first_response AS seconds_first_reply,
      seconds_to_first_response/60.0 AS task_minutes_wait_time,
      task_queue_name AS department,
      COALESCE(cm.number_of_departments,0) AS number_of_departments,
      COALESCE(cm.number_of_tasks,0) AS number_of_tasks,
      FIRST_VALUE(task_queue_name) OVER (PARTITION BY c.id_conversation ORDER BY t.ts_created) AS first_department,
      LAST_VALUE(task_queue_name) OVER (PARTITION BY c.id_conversation ORDER BY t.ts_created) AS last_department, 
      CASE
          WHEN seconds_to_first_response / 60 <= 15 THEN TRUE
          WHEN seconds_to_first_response / 60 > 15 THEN FALSE
          ELSE NULL
      END AS sla_achieved,
      customer_type_tag,
      contact_motivation_tag,
      contact_theme_tag,
      c.seconds_duration/60.0 AS minutes_full_resolution_time_calendar,
      t.ts_created,
      t.ts_updated,
      tt.ts_task_closed,
      tt.ts_task_created,
      ts_twilio_created_local,
      ts_twilio_updated_local,
      cm.ts_first_event,
      cm.ts_last_event
    FROM
      datalake_quinto_messenger.channel c
    LEFT JOIN
      chat_metrics cm
        ON cm.id_conversation = c.id_source
    LEFT JOIN
      datalake_quinto_messenger.task t
        ON t.id_channel = c.id_channel
    LEFT JOIN
      datalake_gsheets_clean.agents_control ac
        ON t.agent_email = ac.email
    JOIN
      last_updated_task lup
        ON t.id_task = lup.id_task
        AND t.ts_updated = lup.ts_last_updated
    JOIN
      datalake_quinto_messenger.task_event te
        ON t.id_task = te.id_task
    LEFT JOIN
      task_timestamps tt
        ON tt.id_task = t.id_task
    WHERE
        c.ts_created > '2020-08-20'
        AND c.channel_status <> 'missed'
),
zendesk_aditional_ticket_info AS (
  SELECT DISTINCT 
    tf.id_ticket,
    ftm.id_session,
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
    ftm.id_session IS NOT NULL
),
chat_csat AS(
  SELECT
        c.id_ticket,
        sa.rating AS csat_score,
        c.group_name,
        sa.comment,
        CASE
            WHEN sa.is_solved = TRUE THEN TRUE
            WHEN sa.is_solved = FALSE THEN FALSE
            ELSE NULL
        END AS is_solved,
        DATE(c.ts_attended) AS dt_survey
  FROM
      datalake_chat_fup_clean.chats_chat c
  JOIN 
      datalake_chat_fup_clean.surveys_survey ss 
          ON ss.id_chat = c.id
  LEFT JOIN 
      datalake_chat_fup_clean.surveys_answer sa 
          ON ss.id = sa.id_survey
  WHERE
      sa.id IS NOT NULL
      AND DATE(c.ts_attended) >= DATE('2018-01-01')
),
back_tickets AS (
  SELECT
    zd.id_ticket AS back_ticket,
    zd.status AS back_ticket_status,
    zd2.id_ticket AS front_ticket,
    REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})',1) AS front_task
  FROM
    zendesk_aditional_ticket_info zd
  JOIN
    quinto_messenger_tickets qmt
      ON qmt.id_task = REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})',1)
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = zd.zendesk_ticket_department 
  JOIN
    zendesk_aditional_ticket_info zd2
      ON qmt.id_session = zd2.id_session
  WHERE
    (zd.tags LIKE '%tarefa_atendimento_escalado%' OR LOWER(dc.front_or_back) = 'back')
    AND (zd.tags NOT LIKE '%bot_end_conversation%' AND zd.tags NOT LIKE '%closed_by_merge%')
    AND REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})',1) != '' 
  GROUP BY 1,2,3,4
),
task_completion_reason AS (
    SELECT
        id_task,
        task_queue_name,
        task_completion_reason
    FROM 
      datalake_quinto_messenger.task_event
    WHERE 
      task_completion_reason = 'task transferred' 
    GROUP BY 1, 2, 3
)
SELECT DISTINCT 
  ct.id_task,
  zd.id_ticket,
  ct.id_conversation,
  ct.id_session,
  ct.id_agent,
  ct.agent_email,
  ct.agent_manager,
  ct.agent_name,
  ct.agent_company,
  cc.comment AS csat_comment,
  ct.department,
  ct.first_department,
  ct.last_department,
  zd.request_type,
  zd.client_type,
  zd.customer_type_tag,
  zd.contact_motivation_tag,
  zd.contact_theme_tag,
  zd.tags,
  zd.status,
  zd.custom_fields,
  bt.back_ticket,
  ct.seconds_first_reply,
  ct.task_minutes_wait_time,
  ct.number_of_departments,
  ct.number_of_tasks,
  ct.sla_achieved,
  ct.minutes_full_resolution_time_calendar,
  zd.minutes_first_resolution_time_calendar,
  zd.minutes_first_resolution_time_business,
  LAST(ct.id_task) OVER (PARTITION BY zd.id_ticket ORDER BY ct.ts_task_created ASC) = ct.id_task AS is_last_task,
  FIRST(ct.id_task) OVER (PARTITION BY zd.id_ticket ORDER BY ct.ts_task_created ASC) = ct.id_task AS is_first_task,
  tcr.id_task IS NOT NULL AS has_transfers,
  zd.tags LIKE '%bot_end_conversation%' AS is_bot,
  zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge, 
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  CASE
    WHEN bt.back_ticket_status IN ('open','pending','new','hold') THEN TRUE
    WHEN bt.back_ticket_status IN ('closed','deleted','solved') THEN FALSE
  END AS is_open_back_ticket,
  cc.id_ticket IS NOT NULL AS is_csat_answered,
  cc.is_solved,
  cc.csat_score,
  cc.group_name,
  cc.dt_survey,
  ct.ts_created,
  ct.ts_updated,
  ct.ts_first_event AS ts_ticket_started,
  ct.ts_last_event AS ts_ticket_ended,
  ct.ts_task_closed,
  ct.ts_task_created,
  ct.ts_twilio_created_local,
  ct.ts_twilio_updated_local
FROM
  quinto_messenger_tickets ct
JOIN
  zendesk_aditional_ticket_info zd
    ON zd.id_session = ct.id_session
JOIN
  datalake_gsheets_clean.department_control dc
    ON dc.department = ct.department
    AND LOWER(dc.front_or_back) <> 'back'
LEFT JOIN
  task_completion_reason tcr
    ON tcr.id_task = ct.id_task
LEFT JOIN
  chat_csat cc
    ON cc.id_ticket = zd.id_ticket
LEFT JOIN
  back_tickets bt
    ON bt.front_ticket = zd.id_ticket
WHERE 
  zd.tags NOT LIKE '%tarefa_atendimento_escalado%'
