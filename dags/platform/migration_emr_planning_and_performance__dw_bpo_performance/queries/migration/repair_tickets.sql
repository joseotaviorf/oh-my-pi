WITH ticket_events AS (
  SELECT
    te.sk_ticket,
    MIN(te.ts_event) FILTER(WHERE
      te.tags RLIKE 'macro_ro_acao_backlog_full_prestador_interno'
      OR te.tags RLIKE 'acao_backlog_full_prestador_interno'
      OR te.tags RLIKE 'macro_ro_refluxo_tarefa_acionar_parceiro') - INTERVAL '3' HOUR AS ts_reflux,
    MIN(te.ts_event) FILTER(WHERE
      sk_group <> '18592339863437') - INTERVAL '3' HOUR AS ts_first_open,
    MIN(te.ts_event) FILTER(WHERE
      tags RLIKE 'macro_ro_iq_ps_iq_manual'
      OR tags RLIKE 'macro_ro_pp_ps_iq_manual'
      OR tags RLIKE 'testes_ro_especializacao_ps_iq'
      OR tags RLIKE 'pp_escolheu_prestador_iq_aprovar_orcamento'
      OR tags RLIKE 'iq_pp_escolheu_prestador_iq_aprovar_orcamento'
      OR tags RLIKE 'macro_ro_triagem_pp_definido_psiq'
      OR tags RLIKE 'macro_ro_triagem_iq_definido_psiq'
      OR tags RLIKE 'tag_Squad_reparos_reparacao_piloto_ps_iq'
      OR tags RLIKE 'tag_squad_reparos_reparacao_piloto_ps_iq'
      OR tags RLIKE 'tag_squad_reparos_reparacao_piloto_jornada_ps_iq_pp'
      OR tags RLIKE 'tag_squad_reparos_reparacao_piloto_jornada_ps_iq_iq') AS ts_ps_iq,
    MIN(te.ts_event) FILTER(WHERE
      tags RLIKE 'macro_ro_definicao_prestador_proprio'
      OR tags RLIKE 'definição_prestador_proprio'
      OR tags RLIKE 'macro_ro_definicao_prestador_proprio'
      OR tags RLIKE 'testes_ro_especializacao_ps_pp'
      OR tags RLIKE 'pp_autosserviço_prestadorpp'
      OR tags RLIKE 'iq_pp_autosserviço_prestadorpp'
      OR tags RLIKE 'macro_ro_triagem_iq_definido_pspp'
      OR tags RLIKE 'macro_ro_triagem_pp_definido_pspp'
      OR tags RLIKE 'tag_squad_reparos_reparacao_piloto_ps_pp'
      OR tags RLIKE 'tag_Squad_reparos_reparacao_piloto_ps_pp'
      OR tags RLIKE 'tag_squad_reparos_reparacao_piloto_jornada_ps_pp_pp'
      OR tags RLIKE 'tag_squad_reparos_reparacao_piloto_jornada_ps_pp_iq') AS ts_ps_pp,
    MIN(te.ts_event) FILTER(WHERE
      tags RLIKE 'comum_iniciar_compulsoria'
      OR tags RLIKE 'mediação_início_compulsória'
      OR tags RLIKE 'macro_ro_inicio_compulsoria'
      OR tags RLIKE 'macro_ro_compulsoria_iq_inicio_compulsoria'
      OR tags RLIKE 'macro_ro_compulsoria_pp_inicio_compulsoria'
      OR tags RLIKE 'execução_compulsória'
      OR tags RLIKE 'macro_ro_aprovado_compulsória'
      OR tags RLIKE 'testes_ro_especializacao_compulsoria_iq'
      OR tags RLIKE 'aprovação_compulsória_contestação'
      OR tags RLIKE 'compul') AS ts_compulsory
  FROM dw_customer_support.fact_ticket_events AS te
  WHERE
    te.ts_ticket_created >= CAST('2024-01-01' AS DATE)
  GROUP BY
    te.sk_ticket
), status_fup AS (
  SELECT
    id_repair_request,
    ts_help_request
  FROM (
    SELECT
      rrtnf.id_repair_request,
      rrtnf.ts_updated AS ts_help_request,
      ROW_NUMBER() OVER (PARTITION BY rrtnf.id_repair_request ORDER BY rrtnf.ts_updated ASC) AS _w,
      rrtnf.ts_updated
    FROM datalake_repairs_clean.repair_request_tenant_negotiation_follow_up AS rrtnf
    WHERE
      status = 'HELP_NEEDED'
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  id_ticket,
  id_request,
  id_contract,
  group_name,
  client_type,
  status,
  custom_fields,
  tags,
  ticket_via,
  channel,
  agent_email,
  organization,
  contestation_task_origin,
  service_provider,
  theme,
  theme_detail,
  request_type,
  customer_type_tag,
  motivation,
  front_or_back,
  comment_csat,
  csat_tags,
  csat_score,
  csat_partes,
  is_closed_by_merge,
  is_contestation_backlog,
  is_ticket_followup,
  has_chat_negociation,
  reopens,
  replies,
  relisting,
  minutes_first_reply_time_calendar,
  entrance_date,
  ts_contestation,
  ts_resolution_contestation,
  ts_first_interaction,
  ts_created_local,
  ts_updated_local,
  ts_closed_local,
  ts_solved_local,
  ts_request_created,
  ts_csat_response_submitted,
  ts_initially_assigned_local,
  ts_last_assigned_local,
  ts_reflux,
  ts_first_open,
  ts_ps_iq,
  ts_ps_pp,
  ts_compulsory,
  ts_help_request,
  ts_latest_customer_comment,
  ts_latest_analyst_comment,
  year,
  month,
  day,
  ts_load
FROM (
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
    rt.agent_organization AS organization,
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
    te.ts_ps_iq,
    te.ts_ps_pp,
    te.ts_compulsory,
    sf.ts_help_request,
    rt.ts_latest_customer_comment,
    rt.ts_latest_analyst_comment,
    YEAR(TO_DATE(CURRENT_DATE)) AS year,
    MONTH(TO_DATE(CURRENT_DATE)) AS month,
    DAY(TO_DATE(CURRENT_DATE)) AS day,
    NOW() AS ts_load,
    ROW_NUMBER() OVER (PARTITION BY rt.id_ticket ORDER BY MAKE_DATE(
      YEAR(TO_DATE(CURRENT_DATE)),
      MONTH(TO_DATE(CURRENT_DATE)),
      DAY(TO_DATE(CURRENT_DATE))
    ) DESC) AS _w
  FROM datalake_repairs.repair_tickets AS rt
  LEFT JOIN ticket_events AS te
    ON te.sk_ticket = rt.id_ticket
  LEFT JOIN status_fup AS sf
    ON sf.id_repair_request = rt.id_request
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) - INTERVAL '1' YEAR AND CAST('{load_end_date}' AS DATE)
) AS _t
WHERE
  _w = 1
