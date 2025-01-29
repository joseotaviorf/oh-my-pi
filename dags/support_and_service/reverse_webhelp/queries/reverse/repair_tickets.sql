WITH ticket_events AS (
  SELECT
    te.sk_ticket,
    MIN(te.ts_event) FILTER (
      WHERE
        REGEXP_LIKE(te.tags, 'macro_ro_acao_backlog_full_prestador_interno')
        OR REGEXP_LIKE(te.tags,'acao_backlog_full_prestador_interno')
        OR REGEXP_LIKE(te.tags,'macro_ro_refluxo_tarefa_acionar_parceiro')
    ) - INTERVAL 3 HOUR AS ts_reflux,
    MIN(te.ts_event) FILTER (
      WHERE sk_group IN ('11373011255565','10567436267277')
    ) - INTERVAL 3 HOUR AS ts_first_open
  FROM
    dw_customer_support.fact_ticket_events AS te
  WHERE
    te.ts_ticket_created >= DATE('2024-01-01')
  GROUP BY
    te.sk_ticket
),status_fup AS (
SELECT
    rrtnf.id_repair_request,
    rrtnf.ts_updated AS ts_help_request
  FROM
    datalake_repairs_clean.repair_request_tenant_negotiation_follow_up AS rrtnf
  WHERE status = 'HELP_NEEDED'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rrtnf.id_repair_request ORDER BY rrtnf.ts_updated ASC) = 1
)
SELECT
  rt.id_ticket,
  rt.id_request,
  rt.id_contract,
  rt.group_name,
  rt.client_type,
  rt.status,
  rt.custom_fields,
  rt.tags,
  rt.ticket_via,
  rt.channel,
  rt.agent_email,
  rt.agent_organization,
  rt.contestation_task_origin,
  rt.service_provider,
  rt.theme,
  rt.theme_detail,
  rt.request_type,
  rt.customer_type_tag,
  rt.motivation,
  rt.front_or_back,
  rt.comment_csat,
  rt.csat_tags,
  rt.csat_score,
  rt.csat_partes,
  rt.is_closed_by_merge,
  rt.is_contestation_backlog,
  rt.is_ticket_followup,
  rt.has_chat_negociation,
  rt.reopens,
  rt.replies,
  rt.relisting,
  rt.minutes_first_reply_time_calendar,
  rt.entrance_date,
  rt.ts_contestation,
  rt.ts_resolution_contestation,
  rt.ts_first_interaction,
  rt.ts_created_local,
  rt.ts_updated_local,
  rt.ts_closed_local,
  rt.ts_solved_local,
  rt.ts_request_created,
  rt.ts_csat_response_submitted,
  rt.ts_initially_assigned_local,
  rt.ts_last_assigned_local,
  te.ts_reflux,
  te.ts_first_open,
  sf.ts_help_request,
  rt.ts_latest_customer_comment,
  rt.ts_latest_analyst_comment,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  datalake_repairs.repair_tickets AS rt
LEFT JOIN
  ticket_events AS te
    ON te.sk_ticket = rt.id_ticket
LEFT JOIN
  status_fup AS sf
    ON sf.id_repair_request = rt.id_request
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY rt.id_ticket ORDER BY MAKE_DATE(rt.year,rt.month,rt.day) DESC) = 1
