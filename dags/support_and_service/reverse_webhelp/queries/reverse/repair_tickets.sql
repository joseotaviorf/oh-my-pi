WITH ticket_events AS (
  SELECT
    te.sk_ticket,
    CASE
      WHEN REGEXP_LIKE(te.tags,
        'macro_ro_acao_backlog_full_prestador_interno|
        acao_backlog_full_prestador_interno|
        macro_ro_refluxo_tarefa_acionar_parceiro')
      THEN MIN(te.ts_event - INTERVAL 3 HOUR)
    END AS ts_reflux
  FROM
    dw_tickets.fact_ticket_events AS te
  WHERE
    te.ts_ticket_created >= DATE('2024-01-01')
  GROUP BY
    te.sk_ticket, te.tags, te.sk_group
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
  rt.year,
  rt.month,
  rt.day,
  NOW() AS ts_load
FROM
  datalake_repairs.repair_tickets AS rt
LEFT JOIN 
  ticket_events AS te
    ON te.sk_ticket = rt.id_ticket
WHERE
  MAKE_DATE(year, month, day) >= CURRENT_DATE - INTERVAL '1' YEAR
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY rt.id_ticket ORDER BY MAKE_DATE(rt.year,rt.month,rt.day) DESC) = 1