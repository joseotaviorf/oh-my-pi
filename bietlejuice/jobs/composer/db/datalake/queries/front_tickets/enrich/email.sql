WITH zendesk_email AS (
  WITH last_update_ticket AS (
    SELECT 
      id_ticket, 
      MAX(ts_updated) AS ts_last_updated 
    FROM 
      datalake_zendesk_tickets_clean.tickets
    GROUP BY 1
  ),
  last_updated_ticket_metrics AS (
    SELECT
      t.id_ticket, 
      MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated,
      MAX(ts_updated) AS ts_updated
    FROM 
      datalake_zendesk_ticket_funnels.tickets_funnel_metrics t
    GROUP BY 1
  )
  SELECT DISTINCT 
    t.id_ticket,
    t.id_requester,
    t.id_assignee AS id_agent,
    t.tags,
    t.description,
    t.status,
    g.name AS departament,
    CASE
      WHEN CAST(tfm.minutes_requester_wait_business AS INT) / (60.0 * COALESCE(CAST(tfm.replies AS INT),1)) < 6 THEN TRUE
      WHEN CAST(tfm.minutes_requester_wait_business AS INT) / (60.0 * COALESCE(CAST(tfm.replies AS INT),1)) >= 6 THEN FALSE
      ELSE NULL
    END AS is_sla,
    tfm.minutes_full_resolution_calendar AS minutes_full_resolution_time_calendar,
    tfm.minutes_full_resolution_business AS minutes_full_resolution_time_business
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
  JOIN
    last_updated_ticket_metrics lutm
      ON lutm.id_ticket = tfm.id_ticket
      AND lutm.dt_last_updated = DATE(CONCAT(tfm.year, '-', tfm.month, '-', tfm.day))
      AND lutm.ts_updated = tfm.ts_updated
  LEFT JOIN
    datalake_zendesk_tickets_clean.groups g
      ON g.id_group = t.id_group
  WHERE 
    ticket_via = 'email'
),
csat AS (
    WITH last_update_ticket AS (
      SELECT 
        id_ticket, 
        MAX(ts_updated) AS ts_last_updated 
      FROM 
        datalake_zendesk_tickets_clean.tickets
      GROUP BY 1
    )
    SELECT
      t.id_ticket,
      CASE
        WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') = 'bad' THEN  1
        WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') = 'good' THEN  5
        ELSE NULL
      END AS csat_score,
      GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('good', 'bad') AS is_answered,
      CASE
          WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('good') THEN TRUE
          WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('bad') THEN FALSE
      END AS is_solved,
      GET_JSON_OBJECT(satisfaction_rating,'$.reason') AS score_reason,
      GET_JSON_OBJECT(satisfaction_rating,'$.comment') AS csat_comment,
      satisfaction_rating
    FROM
      datalake_zendesk_tickets_clean.tickets t
    JOIN
      last_update_ticket lut
        ON t.id_ticket = lut.id_ticket
        AND t.ts_updated = lut.ts_last_updated
    WHERE 
      ticket_via = 'email'
),
taxonomy AS (
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
      EXPLODE(SPLIT(REPLACE(REPLACE(custom_fields, '{', ''), '}', ''), ',')) AS custom_field
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
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo de contato'), '[', ''), ']', '') AS contact_type_tag,
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Cliente Tag'), '[', ''), ']', '') AS client_type,
    REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Tipo de Solicitação'), '[', ''), ']', '') AS request_type,
    COALESCE(
      ctt.contact_motivation_tag,
      REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo Tag'), '[', ''), ']', '')
    ) AS contact_motivation_tag,
    COALESCE(
      ctt.contact_theme_tag,
      REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Assunto Tag'), '[', ''), ']', '')
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
    datalake_raw.gsheets_contact_types_tags ctt 
      ON ctt.contact_type_tag = REPLACE(REPLACE(GET_JSON_OBJECT(zcf.custom_fields, '$.Motivo de contato'), '[', ''), ']', '')
      AND ctt.is_correspondent_contact_type = 1
),
back_tickets AS (
  SELECT
    id_ticket AS back_ticket,
    status AS back_ticket_status,
    REGEXP_EXTRACT(SUBSTRING(SPLIT(description, 'Ticket do contato')[1], 1, 18), '([0-9]{8})', 1) AS front_ticket
  FROM
    zendesk_email
  WHERE 
    tags LIKE '%tarefa_atendimento_escalado%'
    AND (tags NOT LIKE '%bot_end_conversation%' AND tags NOT LIKE '%closed_by_merge%')
    AND REGEXP_EXTRACT(SUBSTRING(SPLIT(description, 'Ticket do contato')[1], 1, 18), '([0-9]{8})', 1) != ''
)
SELECT DISTINCT 
  ze.id_ticket,
  ze.id_ticket,
  ze.id_requester,
  ze.id_agent,
  ze.tags,
  ze.status,
  ze.departament,
  ze.is_sla,
  ze.minutes_full_resolution_time_calendar,
  ze.minutes_full_resolution_time_business,
  cs.csat_score,
  cs.is_answered,
  cs.is_solved,
  cs.score_reason,
  cs.csat_comment,
  cs.satisfaction_rating,
  t.channel,
  t.custom_fields,
  t.contact_type_tag,
  t.client_type,
  t.request_type,
  t.contact_motivation_tag,
  t.contact_theme_tag,
  ze.tags LIKE '%tarefa_atendimento_escalado%' AS has_back_tickets,
  ze.tags LIKE '%bot_end_conversation%' AS is_bot, 
  ze.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  bt.back_ticket IS NOT NULL has_back_ticket,
  CASE
    WHEN bt.back_ticket_status IN ('open','pending','new','hold') THEN TRUE
    WHEN bt.back_ticket_status IN ('closed','deleted','solved') THEN FALSE
  END AS is_open_back_ticket,
  bt.back_ticket
FROM 
  zendesk_email ze
LEFT JOIN
  csat cs
    ON ze.id_ticket = cs.id_ticket
LEFT JOIN
  taxonomy t
    ON t.id_ticket = ze.id_ticket
    AND t.channel = 'email'
LEFT JOIN
  back_tickets bt
    ON bt.front_ticket = ze.id_ticket
WHERE 
  ze.tags NOT LIKE '%tarefa_atendimento_escalado%'
  -- emails with the tags below are not new demands or automatically closed, therefore, they should not be considered
  AND ze.tags NOT LIKE '%resolve_ticket_acompanhamento%'
  AND ze.tags NOT LIKE '%fechado_automaticamente_noreply%'
  AND ze.tags NOT LIKE '%redirecionado_atendimento_2%'
  AND ze.tags NOT LIKE '%closed_by_merge%'
  AND ze.tags NOT LIKE '%zapdesk%'
  AND ze.tags NOT LIKE '%ticket_via_call%'
  AND ze.tags NOT LIKE '%call_contato_receptivo%'
  AND ze.tags NOT LIKE '%call_contato_ativo%'
  AND ze.tags NOT LIKE '%redirecionado_adm_v1%'