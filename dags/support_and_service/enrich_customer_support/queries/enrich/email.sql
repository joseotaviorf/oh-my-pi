-- TO RUN ON DATABRICKS: replace double brackets ('{{', '}}') for single ones
WITH zendesk_email AS (
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
    tf.agent_email,
    tf.request_type,
    tf.client_type,
    tf.step_tag,
    tf.customer_type_tag,
    tf.contact_motivation_tag,
    tf.contact_theme_tag,
    tf.contact_theme_detail_tag,
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
    tfm.reopens,
    tfm.replies,
    tfm.ts_initially_assigned_local,
    tfm.ts_last_assigned_local,
    tfm.ts_created_local AS ts_ticket_started,
    tfm.ts_solved_local AS ts_ticket_solved,
    tfm.ts_closed_local AS ts_ticket_ended
  FROM
    datalake_zendesk_tickets_clean.tickets t
  INNER JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
      ON t.id_ticket = tfm.id_ticket
  INNER JOIN
    datalake_zendesk_ticket_funnels.ticket_funnel tf
      ON t.id_ticket = tf.id_ticket
  LEFT JOIN
    datalake_zendesk_tickets_clean.groups g
      ON g.id_group = t.id_group
  WHERE
    tfm.id_session IS NULL
    AND tfm.id_call IS NULL
),
csat AS (
  SELECT
    id_ticket,
    GET_JSON_OBJECT(satisfaction_rating, '$.comment') AS csat_comment,
    GET_JSON_OBJECT(satisfaction_rating, '$.reason') AS score_reason,
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
    ts_updated AS ts_response
  FROM
    datalake_zendesk_tickets_clean.tickets_history
  WHERE
    GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('good', 'bad')
  UNION ALL
  SELECT
    id_ticket,
    user_comment AS csat_comment,
    NULL AS score_reason,
    csat_score,
    COALESCE(CAST(user_comment AS STRING), CAST(csat_score AS STRING), CAST(is_solved AS STRING)) IS NOT NULL AS is_answered,
    is_solved,
    ts_first_response  AS ts_response
  FROM
    datalake_survicate.zendesk_email_surveys
  WHERE
    id_ticket IS NOT NULL
    AND COALESCE(CAST(user_comment AS STRING), CAST(csat_score AS STRING), CAST(is_solved AS STRING)) IS NOT NULL
),
csat_answers AS (
  SELECT
    id_ticket,
    csat_comment,
    score_reason,
    csat_score,
    is_answered,
    is_solved,
    ts_response,
    ROW_NUMBER() OVER (PARTITION BY id_ticket ORDER BY ts_response DESC) AS rw_number_desc,
    ROW_NUMBER() OVER (PARTITION BY id_ticket ORDER BY ts_response) AS rw_number_asc
  FROM
    csat
),
csat_first_and_last_ts AS (
  SELECT
    ca.id_ticket,
    ca.csat_comment AS last_csat_comment,
    ca2.csat_comment AS first_csat_comment,
    ca.score_reason,
    ca.csat_score AS last_csat_score,
    ca2.csat_score AS first_csat_score,
    ca.is_answered,
    ca.is_solved,
    ca.ts_response AS ts_last_response,
    ca2.ts_response AS ts_first_response
  FROM
    csat_answers AS ca
  INNER JOIN
    csat_answers AS ca2
      ON ca2.id_ticket = ca.id_ticket
      AND ca2.rw_number_asc = 1
  WHERE
    ca.rw_number_desc = 1
),
back_tickets AS (
  SELECT
    id_ticket AS back_ticket,
    status AS back_ticket_status,
    COALESCE(
      NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(custom_fields, '$.Ticket do contato'), '([0-9]{{8}})', 1), ''),
      REGEXP_EXTRACT(SUBSTRING(SPLIT(REGEXP_REPLACE(description, 'WT[a-z0-9]{{20,40}}',''), 'Ticket do contato')[1], 1, 18), '([0-9]{{8}})', 1)
    ) AS front_ticket,
    ts_ticket_started,
    ts_ticket_solved
  FROM
    zendesk_email
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = zendesk_email.department
  WHERE
    (tags LIKE '%tarefa_atendimento_escalado%' OR LOWER(dc.front_or_back) = 'back')
    AND (tags NOT LIKE '%bot_end_conversation%' AND tags NOT LIKE '%closed_by_merge%')
    AND COALESCE(
      NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(custom_fields, '$.Ticket do contato'), '([0-9]{{8}})', 1), ''),
      REGEXP_EXTRACT(SUBSTRING(SPLIT(REGEXP_REPLACE(description, 'WT[a-z0-9]{{20,40}}',''), 'Ticket do contato')[1], 1, 18), '([0-9]{{8}})', 1)
    ) != ''
),
last_and_first_back_tickets_timestamps AS (
  SELECT
    front_ticket,
    CONCAT_WS(',' , COLLECT_SET(back_ticket)) AS back_ticket_list,
    SUM(CAST(back_ticket_status IN ('closed','deleted','solved') AS SMALLINT))/CAST(COUNT(DISTINCT back_ticket) AS FLOAT) != 1 AS is_open_back_ticket,
    MIN(ts_ticket_started) AS ts_first_created,
    MAX(ts_ticket_solved) AS ts_last_solved
  FROM
    back_tickets
  GROUP BY 1
),
last_back_ticket AS (
  SELECT
    bt.*,
    lt.is_open_back_ticket,
    lt.back_ticket_list,
    lt.ts_first_created,
    CAST((TO_UNIX_TIMESTAMP(lt.ts_last_solved) - TO_UNIX_TIMESTAMP(lt.ts_first_created))/60.0 AS DOUBLE) AS total_backoffice_minutes_time
  FROM
    back_tickets bt
  INNER JOIN
    last_and_first_back_tickets_timestamps lt
      ON lt.front_ticket = bt.front_ticket
      AND lt.ts_last_solved = bt.ts_ticket_solved
)
SELECT DISTINCT
  ze.id_ticket,
  ze.id_requester,
  ze.id_agent,
  ze.id_user,
  ze.id_contract,
  ze.agent_email,
  CASE
    WHEN ze.tags LIKE '%"ticket_ativo"%' THEN 'outbound'
    ELSE 'inbound'
  END AS direction,
  ze.tags,
  ze.status,
  ze.department,
  ze.is_sla,
  CAST(ze.minutes_full_resolution_time_calendar AS DOUBLE) AS minutes_full_resolution_time_calendar,
  ze.minutes_full_resolution_time_business,
  ze.minutes_first_response,
  ze.replies,
  ze.reopens,
  cs.first_csat_score,
  cs.last_csat_score AS csat_score,
  cs.is_answered,
  cs.is_solved,
  cs.score_reason,
  cs.first_csat_comment,
  cs.last_csat_comment AS csat_comment,
  ze.channel,
  ze.custom_fields,
  ze.request_type,
  ze.client_type,
  ze.step_tag,
  ze.customer_type_tag,
  ze.contact_motivation_tag,
  ze.contact_theme_tag,
  ze.contact_theme_detail_tag,
  dc.journey_step,
  dc.team,
  dc.area,
  bt.front_ticket IS NOT NULL AS has_back_tickets,
  ze.tags LIKE '%bot_end_conversation%' AS is_bot,
  ze.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  CASE
    WHEN dc.front_or_back = 'Front' THEN 'front'
    WHEN dc.front_or_back = 'Back' OR ze.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
    ELSE 'undefined'
  END AS front_or_back,
  bt.back_ticket IS NOT NULL has_back_ticket,
  CAST((TO_UNIX_TIMESTAMP(COALESCE(bt.ts_ticket_solved, ze.ts_ticket_solved)) - TO_UNIX_TIMESTAMP(ze.ts_ticket_started))/60.0 AS DOUBLE) AS frt,
  bt.is_open_back_ticket,
  bt.back_ticket_list,
  bt.back_ticket AS last_back_ticket,
  bt.total_backoffice_minutes_time,
  CAST((TO_UNIX_TIMESTAMP(bt.ts_first_created) - TO_UNIX_TIMESTAMP(ze.ts_ticket_solved))/60.0 AS DOUBLE) AS total_minutes_front_to_open_back_ticket_time,
  cs.ts_first_response AS ts_csat_first_response,
  cs.ts_last_response AS ts_csat_last_response,
  ze.ts_initially_assigned_local,
  ze.ts_last_assigned_local,
  ze.ts_ticket_started,
  ze.ts_ticket_solved,
  ze.ts_ticket_ended
FROM
  zendesk_email AS ze
LEFT JOIN
  datalake_gsheets_clean.department_control AS dc
    ON dc.department = ze.department
LEFT JOIN
  csat_first_and_last_ts AS cs
    ON ze.id_ticket = cs.id_ticket
LEFT JOIN
  last_back_ticket AS bt
    ON bt.front_ticket = ze.id_ticket
WHERE
  ze.channel IN ('email', 'form_faq', 'web', 'other', 'whatsapp')
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
