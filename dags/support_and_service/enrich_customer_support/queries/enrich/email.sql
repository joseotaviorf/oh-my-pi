-- TO RUN ON DATABRICKS: replace double brackets ('{', '}') for single ones
WITH zendesk_email AS (
  SELECT
    id_ticket,
    id_requester,
    id_assignee AS id_agent,
    id_user_main AS id_user,
    id_contract,
    tags,
    description,
    status,
    group_name AS department,
    analyst_email AS agent_email,
    request_type,
    client_type,
    step_tag,
    customer_type_tag,
    contact_motivation_tag,
    contact_theme_tag,
    contact_theme_detail_tag,
    channel,
    custom_fields,
    CASE
      WHEN CAST(requester_wait_time_min_business AS INT) / (60.0 * COALESCE(CAST(replies AS INT),1)) < 6 THEN TRUE
      WHEN CAST(requester_wait_time_min_business AS INT) / (60.0 * COALESCE(CAST(replies AS INT),1)) >= 6 THEN FALSE
      ELSE NULL
    END AS is_sla,
    requester_wait_time_min_business AS minutes_first_response,
    full_resolution_time_min_calendar AS minutes_full_resolution_time_calendar,
    full_resolution_time_min_business AS minutes_full_resolution_time_business,
    reopens,
    replies,
    ts_initially_assigned  - INTERVAL 3 HOUR AS ts_initially_assigned_local,
    ts_assigned - INTERVAL 3 HOUR AS ts_last_assigned_local,
    ts_created - INTERVAL 3 HOUR AS ts_ticket_started,
    ts_solved - INTERVAL 3 HOUR  AS ts_ticket_solved,
    ts_closed - INTERVAL 3 HOUR  AS ts_ticket_ended
  FROM
    datalake_zendesk.tickets_current
  WHERE
    id_session IS NULL
    AND id_call IS NULL
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
    datalake_zendesk_clean.tickets
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
  WHERE
    csat_score IS NOT NULL
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
      NULLIF(REGEXP_EXTRACT(custom_fields['Ticket do contato'], '([0-9]{{8}})', 1), ''),
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
      NULLIF(REGEXP_EXTRACT(custom_fields['Ticket do contato'], '([0-9]{{8}})', 1), ''),
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
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY bt.front_ticket ORDER BY lt.ts_first_created DESC) = 1
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
  cs.last_csat_score AS csat_score,
  cs.first_csat_score,
  cs.last_csat_score,
  cs.is_answered,
  cs.is_solved,
  cs.score_reason,
  cs.last_csat_comment AS csat_comment,
  cs.first_csat_comment,
  cs.last_csat_comment,
  ze.channel,
  TO_JSON(ze.custom_fields) AS custom_fields,
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
