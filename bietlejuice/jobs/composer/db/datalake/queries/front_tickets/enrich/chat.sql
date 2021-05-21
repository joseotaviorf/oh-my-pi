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
      tc.ts_task_closed,
      ts.ts_task_created,
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
  ),
  filtered_custom_fields AS (
    SELECT
      zcf.id_ticket,
      EXPLODE(SPLIT(REPLACE(REPLACE(custom_fields, '{{', ''), '}}', ''), ',')) AS custom_field
    FROM 
      datalake_clean.zendesk_custom_fields zcf
  ),
  parsed_custom_fields AS (
    SELECT DISTINCT
      id_ticket,
      REGEXP_EXTRACT(custom_field, '"(.*)":(.*)', 1) AS id_ticket_fields,
      REPLACE(REGEXP_EXTRACT(custom_field, '"(.*)":(.*)', 2), '"', '') AS value,
      tf.raw_title AS key
    FROM 
      filtered_custom_fields tcf
    JOIN
      datalake_zendesk_tickets_clean.ticket_fields tf
        ON tf.id_ticket_fields = regexp_extract(custom_field, '"(.*)":(.*)', 1)
  ),
  zendesk_custom_fields AS (
    SELECT
      id_ticket,
      TO_JSON(MAP_FROM_ARRAYS(COLLECT_LIST(key), COLLECT_LIST(value))) AS custom_fields
    FROM
      parsed_custom_fields
    GROUP BY 1
  )
  SELECT 
    DISTINCT t.id_ticket,
    ftm.id_session,
    t.tags,
    t.description,
    t.status,
    zcf.custom_fields,
    ftm.minutes_first_resolution_calendar AS minutes_first_resolution_time_calendar,
    ftm.minutes_first_resolution_business AS minutes_first_resolution_time_business,
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo de contato'), '[', ''), ']', '') AS contact_type_tag,
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Cliente Tag'), '[', ''), ']', '') AS client_type,
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Tipo de Solicitação'), '[', ''), ']', '') AS request_type,
    COALESCE(
      ctt.contact_motivation_tag,
      REPLACE(REPLACE(get_json_object(zcf.custom_fields, '$.Motivo Tag'), '[', ''), ']', '')
    ) AS contact_motivation_tag,
    COALESCE(
      ctt.contact_theme_tag,
      REPLACE(REPLACE(get_json_object(zcf.custom_fields, '$.Assunto Tag'), '[', ''), ']', '')
    ) AS contact_theme_tag
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
  LEFT JOIN
    zendesk_custom_fields zcf
      ON zcf.id_ticket = t.id_ticket
  LEFT JOIN
    datalake_gsheets_clean.contact_type_taxonomy ctt 
      ON ctt.contact_type_tag = REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo de contato'), '[', ''), ']', '')
      AND ctt.is_correspondent_contact_type = 1
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
  ct.id_task,
  zd.id_ticket,
  ct.id_conversation,
  ct.id_session,
  ct.id_agent,
  cc.comment AS csat_comment,
  ct.department,
  ct.first_department,
  ct.last_department,
  COALESCE(
      ct.customer_type_tag,
      zd.client_type
  ) AS client_type,
  COALESCE(
      ct.contact_motivation_tag,
      zd.contact_motivation_tag
  ) AS contact_motivation_tag,
  COALESCE(
    ct.contact_theme_tag,
    zd.contact_theme_tag
  ) AS contact_theme_tag,
  zd.contact_type_tag,
  zd.request_type,
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
