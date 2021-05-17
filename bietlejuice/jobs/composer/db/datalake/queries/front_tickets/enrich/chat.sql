WITH quinto_messenger_tickets AS (
  WITH last_updated_task AS (
      SELECT
        id_task, 
        MAX(ts_updated) AS ts_last_updated 
      FROM datalake_quinto_messenger.task
      GROUP BY 1
  ),
  task_started AS (
    SELECT
        id_task,
        ts_created_local AS ts_task_created
    FROM
        datalake_quinto_messenger.task_event
    WHERE
        type = 'reservation.accepted'
    GROUP BY 1,2
  ),
  task_closed AS (
    SELECT
      id_task,
      ts_created_local AS ts_task_closed
    FROM
      datalake_quinto_messenger.task_event
    WHERE 
      type IN ('reservation.completed', 'reservation.rejected', 'reservation.timeout')
    GROUP BY 1,2
  )
  SELECT
      t.id_task,
      c.id_conversation,
      c.id_source AS id_session,
      id_agent,
      seconds_to_first_response AS seconds_first_reply,
      task_queue_name AS departament,
      FIRST_VALUE(task_queue_name) OVER (PARTITION BY c.id_conversation ORDER BY t.ts_created) AS first_departament,
      LAST_VALUE(task_queue_name) OVER (PARTITION BY c.id_conversation ORDER BY t.ts_created) AS last_departament, 
      CASE
          WHEN seconds_to_first_response / 60 <= 15 THEN TRUE
          WHEN seconds_to_first_response / 60 > 15 THEN FALSE
          ELSE NULL
      END AS sla_achieved,
      customer_type_tag AS client,
      contact_motivation_tag AS motivation,
      contact_theme_tag AS theme,
      c.seconds_duration/60.0 AS minutes_full_resolution_time_calendar,
      t.ts_created,
      t.ts_updated,
      tc.ts_task_closed,
      ts.ts_task_created,
      ts_twilio_created_local,
      ts_twilio_updated_local  
    FROM
      datalake_quinto_messenger.channel c
    LEFT JOIN
      datalake_quinto_messenger.task t
        ON t.id_channel = c.id_channel
    JOIN
      last_updated_task lup
        ON t.id_task = lup.id_task
        AND t.ts_updated = lup.ts_last_updated
    JOIN
      datalake_quinto_messenger.task_event te
        ON t.id_task = te.id_task
    LEFT JOIN
      task_closed tc
        ON tc.id_task = t.id_task
    LEFT JOIN
      task_started ts
        ON ts.id_task = t.id_task
    WHERE
        c.ts_created > '2020-08-20'
        AND c.channel_status <> 'missed'
),
zendesk_aditional_ticket_info AS (
  WITH last_updated_ticket_metrics AS (
    SELECT
      id_ticket, 
      MAX(DATE(CONCAT(year,'-',month,'-',day))) AS ts_extracted,
      MAX(ts_updated) AS ts_updated
    FROM 
      datalake_zendesk_ticket_funnels.tickets_funnel_metrics
    GROUP BY 1
  ),
  last_updated_ticket AS (
    SELECT
      id_ticket, 
      MAX(ts_updated) AS ts_updated
    FROM 
      datalake_zendesk_tickets_clean.tickets
    GROUP BY 1
  )
  SELECT 
    DISTINCT t.id_ticket,
    ftm.id_session,
    t.tags,
    t.description,
    t.status,
    ftm.minutes_first_resolution_calendar AS minutes_first_resolution_time_calendar,
    ftm.minutes_first_resolution_business AS minutes_first_resolution_time_business
  FROM
    datalake_zendesk_tickets_clean.tickets t
  JOIN 
    last_updated_ticket lut
      ON lut.id_ticket = t.id_ticket
      AND lut.ts_updated = t.ts_updated
  JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics ftm
      ON t.id_ticket = ftm.id_ticket
  JOIN
    last_updated_ticket_metrics lutm
      ON ftm.id_ticket = lutm.id_ticket
      AND ftm.ts_updated = lutm.ts_updated
      AND DATE(CONCAT(ftm.year,'-',ftm.month,'-',ftm.day)) = lutm.ts_extracted
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
  JOIN
    zendesk_aditional_ticket_info zd2
      ON qmt.id_session = zd2.id_session
  WHERE
    zd.tags LIKE '%tarefa_atendimento_escalado%'
    AND (zd.tags NOT LIKE '%bot_end_conversation%' AND zd.tags NOT LIKE '%closed_by_merge%')
    AND REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})',1) != '' 
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
  ct.*,
  zd.id_ticket,
  zd.tags,
  zd.minutes_first_resolution_time_calendar,
  zd.minutes_first_resolution_time_business,
  tcr.id_task IS NOT NULL AS task_transfered,
  zd.tags LIKE '%bot_end_conversation%' AS is_bot,
  zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge, 
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  CASE
    WHEN bt.back_ticket_status IN ('open','pending','new','hold') THEN TRUE
    WHEN bt.back_ticket_status IN ('closed','deleted','solved') THEN FALSE
  END AS is_open_back_ticket,
  bt.back_ticket,
  cc.csat_score,
  cc.group_name,
  cc.comment AS csat_comment,
  cc.is_solved,
  cc.dt_survey
FROM
  quinto_messenger_tickets ct
JOIN
  zendesk_aditional_ticket_info zd
    ON zd.id_session = ct.id_session
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
