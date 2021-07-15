/*
In order to run these queries directly from databricks notebook you must replace double 
brackets (`{{` `}}`) for single ones.
*/
WITH quinto_messenger_tickets AS (
  WITH last_updated_task AS (
      SELECT
        id_task, 
        MAX(ts_updated) AS ts_last_updated 
      FROM datalake_quinto_messenger.task
      GROUP BY 1
  ),
  task_transfer_reason AS (
    SELECT DISTINCT
      id_reviewed AS id_task,
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
  ),
  task_timestamps AS (
    SELECT
      id_task,
      MAX(task_queue_name) AS department,
      MAX(ts_created_local) AS ts_task_closed,
      MIN(ts_created_local) AS ts_task_created
    FROM
      datalake_quinto_messenger.task_event
    WHERE 
      type LIKE 'reservation.%'
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
  ),
  task AS (
    SELECT 
      t.id_task,
      t.id_channel,
      t.id_agent,
      t.agent_email,
      department,
      LAG(department,1) OVER (PARTITION BY id_channel ORDER BY tt.ts_task_created) AS transferred_from_dept,
      LEAD(department,1) OVER (PARTITION BY id_channel ORDER BY tt.ts_task_created) AS transferred_to_dept,
      CASE
          WHEN 
            LEAD(department,1) OVER (PARTITION BY id_channel ORDER BY tt.ts_task_created) = department 
            AND LEAD(t.id_agent,1) OVER (PARTITION BY id_channel ORDER BY tt.ts_task_created) = t.id_agent
            THEN 'internal-same-agent'
          WHEN 
            LEAD(department,1) OVER (PARTITION BY id_channel ORDER BY tt.ts_task_created) = department 
            AND LEAD(t.id_agent,1) OVER (PARTITION BY id_channel ORDER BY tt.ts_task_created) != t.id_agent
            THEN 'internal-other-agent'
          WHEN LEAD(department,1) OVER (PARTITION BY id_channel ORDER BY tt.ts_task_created) != department THEN 'external'
      END AS transference_type,
      t.customer_type_tag,
      t.contact_motivation_tag,
      t.contact_theme_tag,
      t.seconds_to_first_response,
      tt.ts_task_closed,
      tt.ts_task_created,
      t.ts_created,
      t.ts_updated
    FROM 
      datalake_quinto_messenger.task t
    JOIN
      last_updated_task lup
        ON t.id_task = lup.id_task
        AND t.ts_updated = lup.ts_last_updated
    JOIN
      task_timestamps tt
        ON tt.id_task = t.id_task
  )
  SELECT
      t.id_task,
      c.id_conversation,
      c.id_source AS id_session,
      t.id_agent,
      t.agent_email,
      ac.manager AS agent_manager,
      ac.agent_name,
      ac.agent_company,
      t.seconds_to_first_response AS seconds_first_reply,
      t.seconds_to_first_response/60.0 AS task_minutes_wait_time,
      t.department,
      t.transferred_from_dept,
      t.transferred_to_dept,
      t.transference_type,
      task_transfer_reason.transference_reason,
      CAST(COALESCE(cm.number_of_departments,0) AS INT) AS number_of_departments,
      CAST(COALESCE(cm.number_of_tasks,0) AS INT) AS number_of_tasks,
      cm.number_of_tasks > 1 AS has_transfers,
      CASE
          WHEN t.seconds_to_first_response / 60 <= 15 THEN TRUE
          WHEN t.seconds_to_first_response / 60 > 15 THEN FALSE
          ELSE NULL
      END AS sla_achieved,
      t.customer_type_tag,
      t.contact_motivation_tag,
      t.contact_theme_tag,
      c.seconds_duration/60.0 AS minutes_full_resolution_time_calendar,
      t.ts_created,
      t.ts_updated,
      t.ts_task_closed,
      t.ts_task_created,
      cm.ts_first_event,
      cm.ts_last_event
    FROM
      datalake_quinto_messenger.channel c
    LEFT JOIN
      chat_metrics cm
        ON cm.id_conversation = c.id_source
    LEFT JOIN
      task t
        ON t.id_channel = c.id_channel
    LEFT JOIN
      task_transfer_reason
        ON task_transfer_reason.id_task = t.id_task
    LEFT JOIN
      datalake_gsheets_clean.agents_control ac
        ON t.agent_email = ac.email
    WHERE
        c.ts_created > '2020-08-20'
        AND c.channel_status <> 'missed'
),
zendesk_tickets_unique AS (
  --this CTE fix the error of multiple tickets openned for a single session
  SELECT
    tfm.id_session,
    MAX(tfm.id_ticket) AS id_ticket
  FROM
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
  JOIN
    datalake_quinto_messenger.channel c
      ON c.id_source = tfm.id_session
  GROUP BY 1
),
zendesk_aditional_ticket_info AS (
  SELECT DISTINCT 
    tf.id_ticket,
    ftm.id_session,
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
    tf.contact_theme_tag
  FROM
    datalake_zendesk_ticket_funnels.ticket_funnel tf
  JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics ftm
      ON tf.id_ticket = ftm.id_ticket
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
        CAST(c.ts_attended AS TIMESTAMP) AS ts_survey
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
    COALESCE(
      NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),
      REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1)
    ) AS front_task
  FROM
    zendesk_aditional_ticket_info zd
  JOIN
    quinto_messenger_tickets qmt
      ON qmt.id_task = COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1))
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = zd.zendesk_ticket_department 
  JOIN
    zendesk_aditional_ticket_info zd2
      ON qmt.id_session = zd2.id_session
  WHERE
    (zd.tags LIKE '%tarefa_atendimento_escalado%' OR LOWER(dc.front_or_back) = 'back')
    AND (zd.tags NOT LIKE '%bot_end_conversation%' AND zd.tags NOT LIKE '%closed_by_merge%')
    AND COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1)) != '' 
  GROUP BY 1,2,3,4
)
SELECT DISTINCT 
  ct.id_task AS id_segment,
  zd.id_ticket,
  ct.id_conversation,
  ct.id_session,
  ct.id_agent,
  FIRST(ct.id_agent) OVER (PARTITION BY zd.id_ticket ORDER BY ct.ts_task_created ASC) AS id_first_agent,
  FIRST(ct.id_agent) OVER (PARTITION BY zd.id_ticket ORDER BY ct.ts_task_created DESC) AS id_last_agent,
  zd.id_user,
  zd.id_contract,
  ct.agent_email,
  ct.agent_manager,
  ct.agent_name,
  ct.agent_company,
  cc.comment AS csat_comment,
  ct.department,
  zd.zendesk_ticket_department AS zendesk_department,
  FIRST(ct.department) OVER (PARTITION BY zd.id_ticket ORDER BY ct.ts_task_created ASC) AS first_department,
  FIRST(ct.department) OVER (PARTITION BY zd.id_ticket ORDER BY ct.ts_task_created DESC) AS last_department,
  ct.transferred_from_dept,
  ct.transferred_to_dept,
  ct.transference_type,
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
  ct.task_minutes_wait_time AS segment_minutes_wait_time,
  ct.number_of_departments,
  ct.number_of_tasks AS number_of_segments,
  ct.sla_achieved,
  CAST(ct.minutes_full_resolution_time_calendar AS DOUBLE) AS minutes_full_resolution_time_calendar,
  zd.minutes_first_resolution_time_calendar,
  zd.minutes_first_resolution_time_business,
  FIRST(ct.id_task) OVER (PARTITION BY zd.id_ticket ORDER BY ct.ts_task_created DESC) = ct.id_task AS is_last_segment,
  FIRST(ct.id_task) OVER (PARTITION BY zd.id_ticket ORDER BY ct.ts_task_created ASC) = ct.id_task AS is_first_segment,
  ct.transference_reason,
  ct.has_transfers,
  zd.tags LIKE '%bot_end_conversation%' AS is_bot,
  zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge, 
  CASE 
    WHEN dc.front_or_back = 'Back' OR zd.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
    WHEN dc.front_or_back = 'Front' OR NULLIF(dc.front_or_back, '-') IS NULL THEN 'front'
  END AS front_or_back,
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  CASE
    WHEN bt.back_ticket_status IN ('open','pending','new','hold') THEN TRUE
    WHEN bt.back_ticket_status IN ('closed','deleted','solved') THEN FALSE
  END AS is_open_back_ticket,
  cc.id_ticket IS NOT NULL AS is_csat_answered,
  cc.is_solved,
  cc.csat_score,
  cc.group_name,
  cc.ts_survey,
  ct.ts_created,
  ct.ts_updated,
  ct.ts_first_event AS ts_ticket_started,
  ct.ts_last_event AS ts_ticket_ended,
  ct.ts_task_closed AS ts_segment_closed,
  ct.ts_task_created AS ts_segment_created
FROM
  quinto_messenger_tickets ct
JOIN
  zendesk_aditional_ticket_info zd
    ON zd.id_session = ct.id_session
JOIN
  zendesk_tickets_unique ztu
    ON ztu.id_ticket = zd.id_ticket
LEFT JOIN
  datalake_gsheets_clean.department_control dc
    ON dc.department = zd.zendesk_ticket_department
LEFT JOIN
  chat_csat cc
    ON cc.id_ticket = zd.id_ticket
LEFT JOIN
  back_tickets bt
    ON bt.front_ticket = zd.id_ticket
