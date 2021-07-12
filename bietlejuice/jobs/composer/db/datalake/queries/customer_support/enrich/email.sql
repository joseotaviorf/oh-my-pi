/*
In order to run these queries directly from databricks notebook you must replace double 
brackets (`{{` `}}`) for single ones.
*/
WITH zendesk_email AS (
  WITH last_update_ticket AS (
    SELECT 
      id_ticket, 
      MAX(ts_updated) AS ts_last_updated 
    FROM 
      datalake_zendesk_tickets_clean.tickets
    GROUP BY 1
  )
  SELECT DISTINCT 
    t.id_ticket,
    t.id_requester,
    t.id_assignee AS id_agent,
    tfm.id_user,
    tfm.id_contract,
    t.tags,
    t.description,
    t.status,
    g.name AS department,
    ac.agent_name,
    ac.agent_company,
    ac.manager AS agent_manager,
    ac.email AS agent_email,
    tf.request_type,
    tf.client_type,
    tf.customer_type_tag,
    tf.contact_motivation_tag,
    tf.contact_theme_tag,
    tf.custom_fields,
    tf.channel,
    tf.custom_fields,
    CASE
      WHEN CAST(tfm.minutes_requester_wait_business AS INT) / (60.0 * COALESCE(CAST(tfm.replies AS INT),1)) < 6 THEN TRUE
      WHEN CAST(tfm.minutes_requester_wait_business AS INT) / (60.0 * COALESCE(CAST(tfm.replies AS INT),1)) >= 6 THEN FALSE
      ELSE NULL
    END AS is_sla,
    tfm.minutes_requester_wait_business AS minutes_first_response,
    tfm.minutes_full_resolution_calendar AS minutes_full_resolution_time_calendar,
    tfm.minutes_full_resolution_business AS minutes_full_resolution_time_business,
    tfm.ts_initially_assigned_local,
    tfm.ts_last_assigned_local,
    tfm.ts_created_local AS ts_ticket_started,
    tfm.ts_solved_local AS ts_ticket_solved,
    tfm.ts_closed_local AS ts_ticket_ended
  FROM
    datalake_zendesk_tickets_clean.tickets t
  JOIN
    last_update_ticket lut
      ON t.id_ticket = lut.id_ticket
      AND t.ts_updated = lut.ts_last_updated
  JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
      ON t.id_ticket = tfm.id_ticket
  JOIN
    datalake_zendesk_ticket_funnels.ticket_funnel tf
      ON t.id_ticket = tf.id_ticket
  LEFT JOIN
    datalake_gsheets_clean.agents_control ac
      ON t.id_assignee = ac.id_assignee
  LEFT JOIN
    datalake_zendesk_tickets_clean.groups g
      ON g.id_group = t.id_group
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
      GET_JSON_OBJECT(satisfaction_rating,'$.comment') AS csat_comment,
      GET_JSON_OBJECT(satisfaction_rating,'$.reason') AS score_reason,
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
      NULL AS ts_first_seen,
      NULL AS ts_first_response
    FROM
      datalake_zendesk_tickets_clean.tickets t
    JOIN
      last_update_ticket lut
        ON t.id_ticket = lut.id_ticket
        AND t.ts_updated = lut.ts_last_updated
    WHERE
      GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('good', 'bad')
    UNION ALL
    SELECT
      id_ticket,
      user_comment AS csat_comment,
      NULL AS score_reason,
      csat_score,
      COALESCE(CAST(user_comment AS STRING),CAST(csat_score AS STRING),CAST(is_solved AS STRING)) IS NOT NULL AS is_answered,
      is_solved,
      ts_first_seen,
      ts_first_response
    FROM
      datalake_survicate.surveys
    WHERE
      id_ticket IS NOT NULL
      AND COALESCE(CAST(user_comment AS STRING),CAST(csat_score AS STRING),CAST(is_solved AS STRING)) IS NOT NULL
),
last_csat_answer AS (
  SELECT
    id_ticket,
    LAST(csat_comment, true) AS csat_comment,
    LAST(score_reason) AS score_reason,
    LAST(csat_score, true) AS csat_score,
    LAST(is_answered, true) AS is_answered,
    LAST(is_solved, true) AS is_solved,
    LAST(ts_first_seen, true) AS ts_first_seen,
    LAST(ts_first_response, true) AS ts_first_response
  FROM
    csat
  GROUP BY 1
  ORDER BY ts_first_response
),
back_tickets AS (
  SELECT
    id_ticket AS back_ticket,
    status AS back_ticket_status,
    COALESCE(
      NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(custom_fields, '$.Ticket do contato'), '([0-9]{{8}})', 1), ''),
      REGEXP_EXTRACT(SUBSTRING(SPLIT(description, 'Ticket do contato')[1], 1, 18), '([0-9]{{8}})', 1)
    ) AS front_ticket
  FROM
    zendesk_email
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = zendesk_email.department 
  WHERE 
    (tags LIKE '%tarefa_atendimento_escalado%' OR LOWER(dc.front_or_back) = 'back')
    AND (tags NOT LIKE '%bot_end_conversation%' AND tags NOT LIKE '%closed_by_merge%')
    AND COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(custom_fields, '$.Ticket do contato'), '([0-9]{{8}})', 1), ''),REGEXP_EXTRACT(SUBSTRING(SPLIT(description, 'Ticket do contato')[1], 1, 18), '([0-9]{{8}})', 1)) != ''
)
SELECT DISTINCT 
  ze.id_ticket,
  ze.id_requester,
  ze.id_agent,
  ze.id_user,
  ze.id_contract,
  ze.agent_name,
  ze.agent_company,
  ze.agent_manager,
  ze.agent_email,
  ze.tags,
  ze.status,
  ze.department,
  ze.is_sla,
  CAST(ze.minutes_full_resolution_time_calendar AS DOUBLE) AS minutes_full_resolution_time_calendar,
  ze.minutes_full_resolution_time_business,
  ze.minutes_first_response,
  cs.csat_score,
  cs.is_answered,
  cs.is_solved,
  cs.score_reason,
  cs.csat_comment,
  ze.channel,
  ze.custom_fields,
  ze.request_type,
  ze.client_type,
  ze.customer_type_tag,
  ze.contact_motivation_tag,
  ze.contact_theme_tag,
  bt.front_ticket IS NOT NULL AS has_back_tickets,
  ze.tags LIKE '%bot_end_conversation%' AS is_bot, 
  ze.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  CASE 
    WHEN dc.front_or_back = 'Back' OR ze.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
    WHEN dc.front_or_back = 'Front' OR NULLIF(dc.front_or_back, '-') IS NULL THEN 'front'
  END AS front_or_back,
  bt.back_ticket IS NOT NULL has_back_ticket,
  CASE
    WHEN bt.back_ticket_status IN ('open','pending','new','hold') THEN TRUE
    WHEN bt.back_ticket_status IN ('closed','deleted','solved') THEN FALSE
  END AS is_open_back_ticket,
  bt.back_ticket,
  cs.ts_first_seen AS ts_csat_first_seen,
  cs.ts_first_response AS ts_csat_first_response,
  ze.ts_initially_assigned_local,
  ze.ts_last_assigned_local,
  ze.ts_ticket_started,
  ze.ts_ticket_solved,
  ze.ts_ticket_ended
FROM 
  zendesk_email ze
LEFT JOIN
  datalake_gsheets_clean.department_control dc
    ON dc.department = ze.department
LEFT JOIN
  last_csat_answer cs
    ON ze.id_ticket = cs.id_ticket
LEFT JOIN
  back_tickets bt
    ON bt.front_ticket = ze.id_ticket
WHERE 
  ze.channel IN ('email', 'form_faq', 'web', 'other')
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
