WITH repair_request_chat AS (
  SELECT
    sk_repair_request,
    ts_started
  FROM (
    SELECT
      id_repair_request AS sk_repair_request,
      ts_started,
      ROW_NUMBER() OVER (PARTITION BY id_repair_request ORDER BY ts_started ASC) AS _w,
      id_repair_request
    FROM datalake_repairs_clean.repair_request_chat
  ) AS _t
  WHERE
    _w = 1
), repair_request_budget AS (
  SELECT
    sk_repair_request,
    id_budget_sender
  FROM (
    SELECT
      id_repair_request AS sk_repair_request,
      id_budget_sender,
      ROW_NUMBER() OVER (PARTITION BY id_repair_request ORDER BY ts_updated DESC) AS _w,
      id_repair_request,
      ts_updated
    FROM datalake_repairs_clean.repair_request_budget
  ) AS _t
  WHERE
    _w = 1
), ticket_events AS (
  SELECT
    te.sk_ticket,
    MIN(te.ts_event) FILTER(WHERE
      te.tags RLIKE 'macro_ro_acao_backlog_full_prestador_interno'
      OR te.tags RLIKE 'acao_backlog_full_prestador_interno'
      OR te.tags RLIKE 'macro_ro_refluxo_tarefa_acionar_parceiro') - INTERVAL '3' HOUR AS ts_reflux,
    MIN(te.ts_event) FILTER(WHERE
      te.tags RLIKE 'pp_autosserviço_contestou'
      OR te.tags RLIKE 'iq_pp_autosserviço_contestou'
      OR te.tags RLIKE 'alteração_de_responsabilidade_criticidade'
      OR te.tags RLIKE 'acompanhamento_alteracao_responsabilidade_criticidade'
      OR te.tags RLIKE 'check_responsabilidade_reparos'
      OR te.tags RLIKE 'pp_autosserviço_contestou') - INTERVAL '3' HOUR AS ts_contestation,
    MIN(te.ts_event) FILTER(WHERE
      te.tags RLIKE 'macro_ro_cont_benfeitoria_pp'
      OR te.tags RLIKE 'macro_ro_cont_benfeitoria_iq'
      OR te.tags RLIKE 'macro_ro_cont_terceiros_pp'
      OR te.tags RLIKE 'macro_ro_cont_terceiros_iq'
      OR te.tags RLIKE 'macro_ro_cont_aprovada_iq'
      OR te.tags RLIKE 'macro_ro_cont_aprovada_pp'
      OR te.tags RLIKE 'macro_ro_cont_reprovada_pp'
      OR te.tags RLIKE 'macro_ro_cont_reprovada_iq'
      OR te.tags RLIKE 'closed_by_merge'
      OR te.tags RLIKE 'reprovado_ro'
      OR te.tags RLIKE 'aprovado_ro'
      OR te.tags RLIKE 'opcional_ro'
      OR te.tags RLIKE 'ação_backlog_contestação'
      OR te.tags RLIKE 'alteração_reprovada'
      OR te.tags RLIKE 'alteração_aprovada'
      OR te.tags RLIKE 'alteração_benfeitoria') - INTERVAL '3' HOUR AS ts_resolution_contestation,
    MIN(te.ts_event) FILTER(WHERE
      sk_group <> '18592339863437') - INTERVAL '3' HOUR AS ts_first_open,
    MIN(
      CASE
        WHEN (
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
          OR tags RLIKE 'tag_squad_reparos_reparacao_piloto_jornada_ps_iq_iq'
        )
        AND sk_group IN ('18592339863437' /* Autosserviço Reparos [BACK] */, '10567436267277' /* FullService [BACK] */, '11373011255565' /* Reparos [BACK] */, '10054637827597' /* Triagem Reparos [Back] */, '32017711499661' /* ReparAção (Piloto Urgente) */, '36385276117261' /* ReparAção Comum [BACK] */, '36464344850701' /* Reparos PP Multi [BACK] */)
        THEN ts_event
      END
    ) AS ts_ps_iq,
    MIN(
      CASE
        WHEN (
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
          OR tags RLIKE 'tag_squad_reparos_reparacao_piloto_jornada_ps_pp_iq'
        )
        AND sk_group IN ('18592339863437' /* Autosserviço Reparos [BACK] */, '10567436267277' /* FullService [BACK] */, '11373011255565' /* Reparos [BACK] */, '10054637827597' /* Triagem Reparos [Back] */, '32017711499661' /* ReparAção (Piloto Urgente) */, '36385276117261' /* ReparAção Comum [BACK] */, '36464344850701' /* Reparos PP Multi [BACK] */)
        THEN ts_event
      END
    ) AS ts_ps_pp,
    MIN(
      CASE
        WHEN (
          tags RLIKE 'comum_iniciar_compulsoria'
          OR tags RLIKE 'mediação_início_compulsória'
          OR tags RLIKE 'macro_ro_inicio_compulsoria'
          OR tags RLIKE 'macro_ro_compulsoria_iq_inicio_compulsoria'
          OR tags RLIKE 'macro_ro_compulsoria_pp_inicio_compulsoria'
          OR tags RLIKE 'execução_compulsória'
          OR tags RLIKE 'macro_ro_aprovado_compulsória'
          OR tags RLIKE 'testes_ro_especializacao_compulsoria_iq'
          OR tags RLIKE 'aprovação_compulsória_contestação'
          OR tags RLIKE 'compul'
        )
        AND sk_group IN ('18592339863437' /* Autosserviço Reparos [BACK] */, '10567436267277' /* FullService [BACK] */, '11373011255565' /* Reparos [BACK] */, '10054637827597' /* Triagem Reparos [Back] */, '32017711499661' /* ReparAção (Piloto Urgente) */, '36385276117261' /* ReparAção Comum [BACK] */, '36464344850701' /* Reparos PP Multi [BACK] */)
        THEN ts_event
      END
    ) AS ts_compulsory,
    MIN(te.ts_event) FILTER(WHERE
      te.tags RLIKE 'reopen_não_encerrado' OR te.tags RLIKE 'reopen_reparos') - INTERVAL '3' HOUR AS ts_reopen,
    MIN(te.ts_event) FILTER(WHERE
      te.tags RLIKE 'comum_iniciar_compulsoria'
      OR te.tags RLIKE 'mediação_início_compulsória'
      OR te.tags RLIKE 'macro_ro_inicio_compulsoria'
      OR te.tags RLIKE 'compulsoria_orcamento_aprovado'
      OR te.tags RLIKE 'macro_ro_definicao_prestador_proprio'
      OR te.tags RLIKE 'definição_prestador_proprio'
      OR te.tags RLIKE 'macro_ro_iq_ps_iq_manual'
      OR te.tags RLIKE 'prestador_quintoandar'
      OR te.tags RLIKE 'macro_ro_cont_terceiros'
      OR te.tags RLIKE 'reparo_de_responsabilidade_de_terceiro'
      OR te.tags RLIKE 'produto_responsabilidade_terceiros'
      OR te.tags RLIKE 'macro_ro_pp_ps_iq_manual'
      OR te.tags RLIKE 'macro_ro_compulsoria_pp_inicio_compulsoria'
      OR te.tags RLIKE 'macro_ro_compulsoria_iq_inicio_compulsoria'
      OR te.tags RLIKE 'macro_ro_cont_aprovada_iq'
      OR te.tags RLIKE 'macro_ro_cont_aprovada_pp'
      OR te.tags RLIKE 'macro_ro_cont_terceiros_iq'
      OR te.tags RLIKE 'macro_ro_cont_terceiros_pp'
      OR te.tags RLIKE 'macro_ro_cont_benfeitoria_pp'
      OR te.tags RLIKE 'macro_ro_cont_benfeitoria_iq'
      OR te.tags RLIKE 'testes_ro_especializacao_compulsoria_pp'
      OR te.tags RLIKE 'testes_ro_especializacao_compulsoria_iq'
      OR te.tags RLIKE 'testes_ro_especializacao_ps_iq'
      OR te.tags RLIKE 'testes_ro_especializacao_ps_pp') - INTERVAL '3' HOUR AS ts_manual_service_provider
  FROM dw_customer_support.fact_ticket_events AS te
  WHERE
    te.ts_ticket_created >= CAST('2023-07-01' AS DATE)
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
), ticket_comment_metrics AS (
  SELECT
    tc.id_ticket,
    SUM(CASE WHEN tc.is_public THEN 1 ELSE 0 END) AS total_public_comments,
    SUM(CASE WHEN NOT tc.is_public THEN 1 ELSE 0 END) AS total_private_comments,
    MAX(CASE WHEN is_public AND zu.role = 'end-user' THEN tc.ts_created END) AS ts_latest_customer_comment,
    MAX(CASE WHEN is_public AND zu.role = 'agent' THEN tc.ts_created END) AS ts_latest_analyst_comment
  FROM datalake_zendesk_clean.ticket_comments AS tc
  LEFT JOIN datalake_support_users.zendesk_users AS zu
    ON zu.id_user_zendesk = tc.id_author
  GROUP BY
    1
), tickets_whatsapp AS (
  SELECT
    id_ticket,
    id_contact_ticket
  FROM (
    SELECT
      tc.id_ticket,
      REPLACE(CAST(custom_fields['Ticket do contato'] AS STRING), '#', '') AS id_contact_ticket,
      ROW_NUMBER() OVER (PARTITION BY REPLACE(CAST(custom_fields['Ticket do contato'] AS STRING), '#', '') ORDER BY tc.ts_created DESC) AS _w,
      tc.ts_created,
      custom_fields
    FROM datalake_zendesk.tickets_current AS tc
    WHERE
      tc.group_name IN ('Reparos [BACK]', 'Triagem Reparos [Back]', 'Autosserviço Reparos [BACK]', 'FullService [BACK]', 'ReparAção (Piloto Urgente)', 'ReparAção Comum [BACK]', 'Reparos PP Multi [BACK]', 'Reembolso de Reparos [Back]', 'Triagem [Porto]', 'Atendimento [Porto]')
      AND tc.channel = 'whatsapp'
      AND NOT tc.custom_fields['Ticket do contato'] IS NULL
      AND tc.ts_created >= CAST('2024-01-01' AS DATE)
      AND tc.tags LIKE '%whatsapp_reparos%'
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  sk_ticket,
  sk_ticket_whatsapp,
  sk_contact_ticket,
  sk_request,
  sk_contract,
  sk_user,
  sk_agent,
  sk_budget_sender,
  reopens,
  relisting,
  replies,
  total_public_comments,
  total_private_comments,
  frt,
  days_to_first_reply,
  ldt_fr_minutes,
  csat_score,
  has_chat_negociation,
  is_ongoing,
  is_other_responsability,
  is_reflux,
  is_contestation,
  is_ended_without_return,
  is_execution_confirmed,
  is_audited_ticket,
  is_fup_iq_agreement,
  is_solved_pspp_automation,
  is_selfservice_migration,
  is_closed_by_merge,
  dt_definition,
  dt_chat,
  ts_first_interaction,
  ts_request_created,
  ts_started,
  ts_initially_assigned_local,
  ts_last_assigned_local,
  ts_measurement,
  ts_first_reply_milestone,
  ts_first_public_comment,
  ts_reflux,
  ts_contestation,
  ts_resolution_contestation,
  ts_first_open,
  ts_ps_iq,
  ts_ps_pp,
  ts_compulsory,
  ts_reopen,
  ts_manual_service_provider,
  ts_help_request,
  ts_latest_customer_comment,
  ts_latest_analyst_comment,
  ts_csat_response_submitted,
  ts_created_local,
  ts_solved_local,
  ts_closed_local,
  ts_updated,
  year,
  month,
  day,
  ts_load
FROM (
  SELECT
    CAST(rt.id_ticket AS BIGINT) AS sk_ticket,
    COALESCE(wpp.id_ticket, -1) AS sk_ticket_whatsapp,
    COALESCE(rt.id_contact_ticket, -1) AS sk_contact_ticket,
    COALESCE(rt.id_request, -1) AS sk_request,
    COALESCE(rt.id_contract, -1) AS sk_contract,
    COALESCE(tc.id_user_main, -1) AS sk_user,
    COALESCE(MD5(rt.agent_email), -1) AS sk_agent,
    COALESCE(b.id_budget_sender, -1) AS sk_budget_sender,
    tc.reopens,
    rt.relisting,
    rt.replies,
    tcm.total_public_comments,
    tcm.total_private_comments,
    DATEDIFF(TO_DATE(CAST(tc.ts_solved AS DATE)), TO_DATE(CAST(tc.ts_created AS DATE))) AS frt,
    DATEDIFF(
      TO_DATE(
        TO_TIMESTAMP(
          CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data do first reply "]') AS STRING),
          'dd/MM/yy HH'
        )
      ),
      TO_DATE(tc.ts_created - INTERVAL '3' HOUR)
    ) AS days_to_first_reply,
    tc.reply_time_min_calendar AS ldt_fr_minutes,
    rt.csat_score,
    IF(rt.has_chat_negociation IS NULL, FALSE, rt.has_chat_negociation) AS has_chat_negociation,
    IF(NOT tc.ts_created IS NULL AND tc.ts_solved IS NULL, TRUE, FALSE) AS is_ongoing,
    CASE
      WHEN tc.tags RLIKE 'produto_responsabilidade_terceiros'
      OR tc.tags RLIKE 'macro_ro_cont_terceiros'
      OR tc.tags RLIKE 'macro_ro_cont_terceiros_iq'
      OR tc.tags RLIKE 'macro_ro_cont_terceiros_pp'
      THEN TRUE
      ELSE FALSE
    END AS is_other_responsability,
    CASE
      WHEN tc.tags RLIKE 'macro_ro_acao_backlog_full_prestador_interno'
      OR tc.tags RLIKE 'acao_backlog_full_prestador_interno'
      OR tc.tags RLIKE 'macro_ro_refluxo_tarefa_acionar_parceiro'
      THEN TRUE
      ELSE FALSE
    END AS is_reflux,
    CASE
      WHEN tc.tags RLIKE 'pp_autosserviço_contestou'
      OR tc.tags RLIKE 'iq_pp_autosserviço_contestou'
      OR tc.tags RLIKE 'alteração_de_responsabilidade_criticidade'
      OR tc.tags RLIKE 'acompanhamento_alteracao_responsabilidade_criticidade'
      OR tc.tags RLIKE 'check_responsabilidade_reparos'
      OR tc.tags RLIKE 'pp_autosserviço_contestou'
      THEN TRUE
      ELSE FALSE
    END AS is_contestation,
    CASE
      WHEN tc.tags RLIKE 'ps_iq_encerrado_sem_retorno_iq'
      OR tc.tags RLIKE 'finalização_semcontato_inquilino'
      OR tc.tags RLIKE 'macro_ro_ps_pp_finalização_sem_retorno_iq'
      THEN TRUE
      ELSE FALSE
    END AS is_ended_without_return,
    IF(tc.tags RLIKE 'macro_ro_ps_pp_reparo_executado', TRUE, FALSE) AS is_execution_confirmed,
    CASE
      WHEN tc.tags RLIKE 'ticket_auditado'
      OR tc.tags RLIKE 'ticket_validado_corrigido'
      OR tc.tags RLIKE 'ticket_validado_não_corrigido'
      OR tc.tags RLIKE 'ticket_validado_feedback'
      THEN TRUE
      ELSE FALSE
    END AS is_audited_ticket,
    CASE
      WHEN tc.tags RLIKE 'pp_fup_iq_acordo' OR tc.tags RLIKE 'iq_fup_iq_acordo'
      THEN TRUE
      ELSE FALSE
    END AS is_fup_iq_agreement,
    IF(tc.tags RLIKE 'automacao_ro_resolved_ps_pp_sem_solved', TRUE, FALSE) AS is_solved_pspp_automation,
    IF(tc.tags RLIKE 'ticket_migrado_auto_serviço', TRUE, FALSE) AS is_selfservice_migration,
    IF(tc.tags RLIKE 'closed_by_merge', TRUE, FALSE) AS is_closed_by_merge,
    rt.dt_definition,
    rt.dt_chat,
    rt.ts_first_interaction,
    rt.ts_request_created,
    rrc.ts_started,
    rt.ts_initially_assigned_local,
    rt.ts_last_assigned_local,
    TO_TIMESTAMP(
      CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data Primeiro FUP Manual Realizado"]') AS STRING),
      'dd/MM/yy HH'
    ) AS ts_measurement,
    TO_TIMESTAMP(
      CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data do first reply "]') AS STRING),
      'dd/MM/yy HH'
    ) AS ts_first_reply_milestone,
    CAST(DATE_ADD(
      tc.ts_created - INTERVAL '3' HOUR,
      ROUND((
        (
          tc.reply_time_min_calendar / 60
        ) / 24
      ))
    ) AS TIMESTAMP) AS ts_first_public_comment,
    te.ts_reflux,
    te.ts_contestation,
    te.ts_resolution_contestation,
    te.ts_first_open,
    te.ts_ps_iq,
    te.ts_ps_pp,
    te.ts_compulsory,
    te.ts_reopen,
    te.ts_manual_service_provider,
    sf.ts_help_request,
    tcm.ts_latest_customer_comment,
    tcm.ts_latest_analyst_comment,
    rt.ts_csat_response_submitted,
    tc.ts_created - INTERVAL '3' HOUR AS ts_created_local,
    tc.ts_solved - INTERVAL '3' HOUR AS ts_solved_local,
    tc.ts_closed - INTERVAL '3' HOUR AS ts_closed_local,
    tc.ts_updated,
    tc.year,
    tc.month,
    tc.day,
    NOW() AS ts_load,
    ROW_NUMBER() OVER (PARTITION BY tc.id_ticket ORDER BY tc.ts_updated DESC) AS _w,
    tc.id_ticket
  FROM datalake_zendesk.tickets_current AS tc
  INNER JOIN datalake_repairs.ongoing_repair_tickets AS rt
    ON rt.id_ticket = tc.id_ticket
  LEFT JOIN repair_request_budget AS b
    ON b.sk_repair_request = rt.id_request
  LEFT JOIN repair_request_chat AS rrc
    ON rrc.sk_repair_request = rt.id_request
  LEFT JOIN ticket_events AS te
    ON rt.id_ticket = te.sk_ticket
  LEFT JOIN status_fup AS sf
    ON sf.id_repair_request = rt.id_request
  LEFT JOIN ticket_comment_metrics AS tcm
    ON tcm.id_ticket = tc.id_ticket
  LEFT JOIN tickets_whatsapp AS wpp
    ON wpp.id_contact_ticket = tc.id_ticket
) AS _t
WHERE
  _w = 1
