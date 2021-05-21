WITH zendesk_taxonomy AS (
  WITH last_update_ticket AS (
    SELECT 
      id_ticket, 
      MAX(ts_updated) AS ts_last_updated 
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
    WHERE 
      ts_updated >= '2018-01-01'
      AND ts_updated <= '2020-08-20'
  ),
  parsed_custom_fields AS (
    SELECT 
      id_ticket,
      REGEXP_EXTRACT(custom_field, '"(.*)":(.*)', 1) AS id_ticket_fields,
      REPLACE(REGEXP_EXTRACT(custom_field, '"(.*)":(.*)', 2), '"', '') AS value,
      tf.raw_title AS key
    FROM 
      filtered_custom_fields tcf
    JOIN
      datalake_zendesk_tickets_clean.ticket_fields tf
        ON tf.id_ticket_fields = REGEXP_EXTRACT(custom_field, '"(.*)":(.*)', 1)
  ),
  zendesk_custom_fields AS (
    SELECT
      id_ticket,
      TO_JSON(
        MAP_FROM_ARRAYS(
          COLLECT_LIST(key), 
          COLLECT_LIST(REPLACE(REPLACE(value, '[', ''), ']', ''))
        )
      ) AS custom_fields
    FROM
      parsed_custom_fields
    GROUP BY 1
  )
  SELECT
    t.id_ticket,
    CASE
          WHEN 
              t.ticket_via IN ('api', 'web') 
              AND (tags LIKE '%call_contato_ativo%' OR tags LIKE '%call_contato_receptivo%') 
          THEN 'call'
          WHEN t.ticket_via = 'api' AND tags LIKE '%form%' THEN 'form_faq'
          WHEN t.ticket_via IN ('web', 'email', 'chat') THEN t.ticket_via
          ELSE 'other'
    END AS channel,
    zcf.custom_fields,
    GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo de contato') AS contact_type_tag,
    GET_JSON_OBJECT(zcf.custom_fields, '$.Cliente Tag') AS client_type,
    GET_JSON_OBJECT(zcf.custom_fields, '$.Tipo de Solicitação') AS request_type,
    COALESCE(
      ctt.contact_motivation_tag,
      GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo Tag')
    ) AS contact_motivation_tag,
    COALESCE(
      ctt.contact_theme_tag,
      GET_JSON_OBJECT(zcf.custom_fields, '$.Assunto Tag')
    ) AS contact_theme_tag
  FROM
    datalake_zendesk_tickets_clean.tickets t
  JOIN
    last_update_ticket lut
      ON t.id_ticket = lut.id_ticket
      AND t.ts_updated = lut.ts_last_updated
  JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
      ON t.id_ticket = tfm.id_ticket
      AND tfm.ts_updated = lut.ts_last_updated
  LEFT JOIN
    zendesk_custom_fields zcf
      ON zcf.id_ticket = t.id_ticket
  LEFT JOIN
    datalake_gsheets_clean.contact_type_taxonomy ctt 
      ON ctt.contact_type_tag = GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo de contato')
      AND ctt.is_correspondent_contact_type = 1
),
historical_chat_tickets AS (
  WITH last_updated_ticket_metrics AS (
    SELECT
      id_ticket, 
      MAX(DATE(CONCAT(year,'-',month,'-',day))) AS ts_extracted,
      MAX(ts_updated) AS ts_updated
    FROM 
      datalake_zendesk_ticket_funnels.tickets_funnel_metrics
    GROUP BY 1
  )
  SELECT DISTINCT 
    c.id_ticket,
    NULL AS id_task,
    NULL AS id_conversation,
    NULL AS id_session,
    ce.id_agent,
    CAST(GET_JSON_OBJECT(c.response_time, '$.first') AS DOUBLE) AS seconds_first_reply_time,
    cd.name AS departament,
    FIRST_VALUE(cd.name) OVER (PARTITION BY c.id_ticket ORDER BY c.ts_created) AS first_departament,
    LAST_VALUE(cd.name) OVER (PARTITION BY c.id_ticket ORDER BY c.ts_created) AS last_departament,
    CASE
      WHEN CAST(GET_JSON_OBJECT(c.response_time, '$.first') AS DOUBLE) / 60 <= 15 THEN 1
      WHEN CAST(GET_JSON_OBJECT(c.response_time, '$.first') AS DOUBLE) / 60 > 15 THEN 0
      ELSE NULL
    END AS sla_achieved,
    zt.contact_type_tag,
    zt.contact_motivation_tag,
    zt.contact_theme_tag,
    CAST(c.duration AS DECIMAL)/60.0 AS minutes_full_resolution_time_calendar,
    ftm.minutes_first_resolution_calendar AS minutes_first_resolution_time_calendar,
    ftm.minutes_first_resolution_business AS minutes_first_resolution_time_business,
    c.ts_created,
    c.ts_updated
  FROM
    datalake_zendesk_clean.chats c
  JOIN
    datalake_zendesk.chat_engagements ce
      ON ce.id_chat = c.id
      AND NOT (ce.is_assigned = 'true' AND ce.is_accepted = 'false') 
  LEFT JOIN
    datalake_zendesk_clean.chats_departments cd
      ON c.id_department = cd.id
  LEFT JOIN
    zendesk_taxonomy zt
      ON zt.id_ticket = c.id_ticket
  LEFT JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics ftm
      ON ftm.id_ticket = c.id_ticket
  JOIN
    last_updated_ticket_metrics lutm
      ON ftm.id_ticket = lutm.id_ticket
      AND ftm.ts_updated = lutm.ts_updated
      AND DATE(CONCAT(ftm.year,'-',ftm.month,'-',ftm.day)) = lutm.ts_extracted
  WHERE
    c.tags NOT LIKE '%bot_end_conversation%' -- status = 'missed'
    AND c.ts_created >= '2018-01-01'
    AND c.ts_created <= '2020-08-20'
),
chat_csat AS (
  SELECT
    c.id_ticket,
    sa.rating AS csat_score,
    c.group_name,
    sa.comment,
    CASE
      WHEN sa.is_solved = TRUE THEN 1
      WHEN sa.is_solved = FALSE THEN 0
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
    AND DATE(c.ts_attended) >= DATE'2018-01-01'
)
SELECT DISTINCT
  ct.id_ticket,
  ct.id_agent,
  ct.seconds_first_reply_time,
  ct.departament,
  ct.first_departament,
  ct.last_departament,
  ct.sla_achieved,
  ct.contact_type_tag,
  ct.contact_motivation_tag,
  ct.contact_theme_tag,
  ct.minutes_full_resolution_time_calendar,
  ct.minutes_first_resolution_time_calendar,
  ct.minutes_first_resolution_time_business,
  cc.csat_score,
  cc.group_name,
  cc.comment,
  cc.is_solved,
  cc.dt_survey,
  ct.ts_created,
  ct.ts_updated
FROM 
  historical_chat_tickets ct
LEFT JOIN
  chat_csat cc
    ON cc.id_ticket = ct.id_ticket