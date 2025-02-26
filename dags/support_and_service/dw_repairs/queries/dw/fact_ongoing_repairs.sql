WITH repair_request_chat AS (
  SELECT
    rrc.id_repair_request AS sk_repair_request,
    rrc.ts_started AS ts_started
  FROM
    datalake_repairs_clean.repair_request_chat AS rrc
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rrc.id_repair_request ORDER BY rrc.ts_started ASC) = 1
),
repair_request_budget AS (
  SELECT
    b.id_repair_request AS sk_repair_request,
    b.id_budget_sender AS id_budget_sender
  FROM
    datalake_repairs_clean.repair_request_budget AS b
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY b.id_repair_request ORDER BY b.ts_updated DESC) = 1
)
,ticket_events AS (
  SELECT
    te.sk_ticket,
    MIN(te.ts_event) FILTER (
      WHERE
        REGEXP_LIKE(te.tags, 'macro_ro_acao_backlog_full_prestador_interno')
        OR REGEXP_LIKE(te.tags,'acao_backlog_full_prestador_interno')
        OR REGEXP_LIKE(te.tags,'macro_ro_refluxo_tarefa_acionar_parceiro')
    ) - INTERVAL 3 HOUR AS ts_reflux,
    MIN(te.ts_event) FILTER (
      WHERE
        REGEXP_LIKE (te.tags, 'pp_autosserviço_contestou')
        OR REGEXP_LIKE (te.tags, 'iq_pp_autosserviço_contestou')
        OR REGEXP_LIKE (te.tags, 'alteração_de_responsabilidade_criticidade')
        OR REGEXP_LIKE (te.tags, 'acompanhamento_alteracao_responsabilidade_criticidade')
        OR REGEXP_LIKE (te.tags, 'check_responsabilidade_reparos')
        OR REGEXP_LIKE (te.tags, 'pp_autosserviço_contestou')
    ) - INTERVAL 3 HOUR AS ts_contestation,
    MIN(te.ts_event)  FILTER (
      WHERE
        REGEXP_LIKE(te.tags,'macro_ro_cont_benfeitoria_pp')
        OR REGEXP_LIKE(te.tags,'macro_ro_cont_benfeitoria_iq')
        OR REGEXP_LIKE(te.tags,'macro_ro_cont_terceiros_pp')
        OR REGEXP_LIKE(te.tags,'macro_ro_cont_terceiros_iq')
        OR REGEXP_LIKE(te.tags,'macro_ro_cont_aprovada_iq')
        OR REGEXP_LIKE(te.tags,'macro_ro_cont_aprovada_pp')
        OR REGEXP_LIKE(te.tags,'macro_ro_cont_reprovada_pp')
        OR REGEXP_LIKE(te.tags,'macro_ro_cont_reprovada_iq')
        OR REGEXP_LIKE(te.tags,'closed_by_merge')
        OR REGEXP_LIKE(te.tags,'reprovado_ro')
        OR REGEXP_LIKE(te.tags,'aprovado_ro')
        OR REGEXP_LIKE(te.tags,'opcional_ro')
        OR REGEXP_LIKE(te.tags,'ação_backlog_contestação')
        OR REGEXP_LIKE(te.tags,'alteração_reprovada')
        OR REGEXP_LIKE(te.tags,'alteração_aprovada')
        OR REGEXP_LIKE(te.tags,'alteração_benfeitoria')
    ) - INTERVAL 3 HOUR AS ts_resolution_contestation,
    MIN(te.ts_event) FILTER (
      WHERE sk_group IN
        (
          '11373011255565',
          '10567436267277',
          '32017711499661'
        )
    ) - INTERVAL 3 HOUR AS ts_first_open,
    MIN(
      CASE
        WHEN
        (
          regexp_like(tags,'macro_ro_iq_ps_iq_manual')
          OR regexp_like(tags,'macro_ro_pp_ps_iq_manual')
          OR regexp_like(tags,'testes_ro_especializacao_ps_iq')
          OR regexp_like(tags,'pp_escolheu_prestador_iq_aprovar_orcamento')
          OR regexp_like(tags,'iq_pp_escolheu_prestador_iq_aprovar_orcamento')
          OR regexp_like(tags,'macro_ro_triagem_pp_definido_psiq')
          OR regexp_like(tags,'macro_ro_triagem_iq_definido_psiq')
          OR regexp_like(tags,'tag_Squad_reparos_reparacao_piloto_ps_iq')
          OR regexp_like(tags,'tag_squad_reparos_reparacao_piloto_ps_iq')
          OR regexp_like(tags,'tag_squad_reparos_reparacao_piloto_jornada_ps_iq_pp')
          OR regexp_like(tags,'tag_squad_reparos_reparacao_piloto_jornada_ps_iq_iq')
        )
        AND sk_group IN
        (
          '18592339863437',
          '10567436267277',
          '11373011255565',
          '10054637827597',
          '32017711499661'
        )
      THEN ts_event
    END) AS ts_ps_iq,
    MIN(
      CASE
        WHEN
        (
          regexp_like(tags,'macro_ro_definicao_prestador_proprio')
          OR regexp_like(tags,'definição_prestador_proprio')
          OR regexp_like(tags,'macro_ro_definicao_prestador_proprio')
          OR regexp_like(tags,'testes_ro_especializacao_ps_pp')
          OR regexp_like(tags,'pp_autosserviço_prestadorpp')
          OR regexp_like(tags,'iq_pp_autosserviço_prestadorpp')
          OR regexp_like(tags,'macro_ro_triagem_iq_definido_pspp')
          OR regexp_like(tags,'macro_ro_triagem_pp_definido_pspp')
          OR regexp_like(tags,'tag_squad_reparos_reparacao_piloto_ps_pp')
          OR regexp_like(tags,'tag_Squad_reparos_reparacao_piloto_ps_pp')
          OR regexp_like(tags,'tag_squad_reparos_reparacao_piloto_jornada_ps_pp_pp')
          OR regexp_like(tags,'tag_squad_reparos_reparacao_piloto_jornada_ps_pp_iq')
        )
        AND sk_group IN
          (
            '18592339863437',
            '10567436267277',
            '11373011255565',
            '10054637827597',
            '32017711499661'
          )
            THEN ts_event
        END) AS ts_ps_pp,
    MIN(
      CASE
        WHEN
        (
          regexp_like(tags,'comum_iniciar_compulsoria')
          OR regexp_like(tags,'mediação_início_compulsória')
          OR regexp_like(tags,'macro_ro_inicio_compulsoria')
          OR regexp_like(tags,'macro_ro_compulsoria_iq_inicio_compulsoria')
          OR regexp_like(tags,'macro_ro_compulsoria_pp_inicio_compulsoria')
          OR regexp_like(tags,'execução_compulsória')
          OR regexp_like(tags,'macro_ro_aprovado_compulsória')
          OR regexp_like(tags,'testes_ro_especializacao_compulsoria_iq')
          OR regexp_like(tags,'aprovação_compulsória_contestação')
          OR regexp_like(tags,'compul')
        )
        AND sk_group IN
          (
            '18592339863437',
            '10567436267277',
            '11373011255565',
            '10054637827597',
            '32017711499661'
          )
        THEN ts_event
      END) AS ts_compulsory,
    MIN(te.ts_event) FILTER (
      WHERE
        REGEXP_LIKE(te.tags, 'reopen_não_encerrado')
        OR REGEXP_LIKE(te.tags,'reopen_reparos')
    ) - INTERVAL 3 HOUR AS ts_reopen,
    MIN(te.ts_event) FILTER (
      WHERE
        REGEXP_LIKE(te.tags, 'comum_iniciar_compulsoria')
        OR REGEXP_LIKE(te.tags, 'mediação_início_compulsória')
        OR REGEXP_LIKE(te.tags, 'macro_ro_inicio_compulsoria')
        OR REGEXP_LIKE(te.tags, 'compulsoria_orcamento_aprovado')
        OR REGEXP_LIKE(te.tags, 'macro_ro_definicao_prestador_proprio')
        OR REGEXP_LIKE(te.tags, 'definição_prestador_proprio')
        OR REGEXP_LIKE(te.tags, 'macro_ro_iq_ps_iq_manual')
        OR REGEXP_LIKE(te.tags, 'prestador_quintoandar')
        OR REGEXP_LIKE(te.tags, 'macro_ro_cont_terceiros')
        OR REGEXP_LIKE(te.tags, 'reparo_de_responsabilidade_de_terceiro')
        OR REGEXP_LIKE(te.tags, 'produto_responsabilidade_terceiros')
        OR REGEXP_LIKE(te.tags, 'macro_ro_pp_ps_iq_manual')
        OR REGEXP_LIKE(te.tags, 'macro_ro_compulsoria_pp_inicio_compulsoria')
        OR REGEXP_LIKE(te.tags, 'macro_ro_compulsoria_iq_inicio_compulsoria')
        OR REGEXP_LIKE(te.tags, 'macro_ro_cont_aprovada_iq')
        OR REGEXP_LIKE(te.tags, 'macro_ro_cont_aprovada_pp')
        OR REGEXP_LIKE(te.tags, 'macro_ro_cont_terceiros_iq')
        OR REGEXP_LIKE(te.tags, 'macro_ro_cont_terceiros_pp')
        OR REGEXP_LIKE(te.tags, 'macro_ro_cont_benfeitoria_pp')
        OR REGEXP_LIKE(te.tags, 'macro_ro_cont_benfeitoria_iq')
        OR REGEXP_LIKE(te.tags, 'testes_ro_especializacao_compulsoria_pp')
        OR REGEXP_LIKE(te.tags, 'testes_ro_especializacao_compulsoria_iq')
        OR REGEXP_LIKE(te.tags, 'testes_ro_especializacao_ps_iq')
        OR REGEXP_LIKE(te.tags, 'testes_ro_especializacao_ps_pp')
    ) - INTERVAL 3 HOUR AS ts_manual_service_provider
  FROM
    dw_customer_support.fact_ticket_events AS te
  WHERE
    te.ts_ticket_created >= DATE('2023-07-01')
  GROUP BY te.sk_ticket
)
,status_fup AS (
SELECT
    rrtnf.id_repair_request,
    rrtnf.ts_updated AS ts_help_request
  FROM
    datalake_repairs_clean.repair_request_tenant_negotiation_follow_up AS rrtnf
  WHERE status = 'HELP_NEEDED'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rrtnf.id_repair_request ORDER BY rrtnf.ts_updated ASC) = 1
)
,ticket_comment_metrics AS (
  SELECT
    tc.id_ticket,
    SUM(CASE WHEN tc.is_public THEN 1 ELSE 0 END) AS total_public_comments,
    SUM(CASE WHEN NOT tc.is_public THEN 1 ELSE 0 END) AS total_private_comments,
    MAX(CASE WHEN is_public AND zu.role = 'end-user' THEN tc.ts_created END) AS ts_latest_customer_comment,
    MAX(CASE WHEN is_public AND zu.role = 'agent' THEN tc.ts_created END) AS ts_latest_analyst_comment
  FROM
    datalake_zendesk_clean.ticket_comments AS tc
  LEFT JOIN
    datalake_support_users.zendesk_users AS zu
      ON zu.id_user_zendesk = tc.id_author
  GROUP BY 1
),
tickets_whatsapp AS (
  SELECT
    tc.id_ticket,
    REPLACE(CAST(custom_fields['Ticket do contato'] AS STRING),'#','') AS id_contact_ticket
  FROM
    datalake_zendesk.tickets_current AS tc
  WHERE
    tc.group_name IN
      (
        'Reparos [BACK]',
        'Triagem Reparos [Back]',
        'Autosserviço Reparos [BACK]',
        'FullService [BACK]',
        'ReparAção (Piloto Urgente)'
      )
    AND tc.channel = 'whatsapp'
    AND tc.custom_fields['Ticket do contato'] IS NOT NULL
    AND tc.ts_created >= DATE('2024-01-01')
    AND tc.tags LIKE '%whatsapp_reparos%'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY REPLACE(CAST(custom_fields['Ticket do contato'] AS STRING),'#','')  ORDER BY tc.ts_created DESC) = 1
)
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
  DATEDIFF(DAY, DATE(rt.ts_created_local) , DATE(rt.ts_solved_local) ) AS frt,
  DATEDIFF(DAY, rt.ts_created_local, to_timestamp(CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data do first reply "]') AS STRING),'dd/MM/yy HH')) AS days_to_first_reply,
  tc.reply_time_min_calendar AS ldt_fr_minutes,
  rt.csat_score,
  IF(rt.has_chat_negociation IS NULL, FALSE, rt.has_chat_negociation) AS has_chat_negociation,
  IF(rt.ts_created_local IS NOT NULL AND rt.ts_solved_local IS NULL , TRUE, FALSE) AS is_ongoing,
  CASE
    WHEN regexp_like (tc.tags,'produto_responsabilidade_terceiros')
      OR regexp_like(tc.tags,'macro_ro_cont_terceiros')
      OR regexp_like(tc.tags,'macro_ro_cont_terceiros_iq')
      OR regexp_like(tc.tags,'macro_ro_cont_terceiros_pp')
    THEN True ELSE False
  END AS is_other_responsability,
  CASE
    WHEN regexp_like (tc.tags,'macro_ro_acao_backlog_full_prestador_interno')
      OR regexp_like(tc.tags,'acao_backlog_full_prestador_interno')
      OR regexp_like(tc.tags,'macro_ro_refluxo_tarefa_acionar_parceiro')
      THEN True ELSE False
    END AS is_reflux,
  CASE
    WHEN regexp_like (tc.tags,'pp_autosserviço_contestou')
      OR regexp_like(tc.tags,'iq_pp_autosserviço_contestou')
      OR regexp_like(tc.tags,'alteração_de_responsabilidade_criticidade')
      OR regexp_like(tc.tags,'acompanhamento_alteracao_responsabilidade_criticidade')
      OR regexp_like(tc.tags,'check_responsabilidade_reparos')
      OR regexp_like(tc.tags,'pp_autosserviço_contestou')
    THEN True ELSE False
  END AS is_contestation,
  CASE
    WHEN regexp_like(tc.tags,'ps_iq_encerrado_sem_retorno_iq')
      OR regexp_like(tc.tags,'finalização_semcontato_inquilino')
      OR regexp_like(tc.tags,'macro_ro_ps_pp_finalização_sem_retorno_iq')
    THEN True ELSE FALSE
  END AS is_ended_without_return,
  IF(regexp_like(tc.tags,'macro_ro_ps_pp_reparo_executado'), True, False) AS is_execution_confirmed,
  CASE
    WHEN regexp_like (tc.tags,'ticket_auditado')
      OR regexp_like(tc.tags,'ticket_validado_corrigido')
      OR regexp_like(tc.tags,'ticket_validado_não_corrigido')
      OR regexp_like(tc.tags,'ticket_validado_feedback')
    THEN True ELSE FALSE
  END AS is_audited_ticket,
  CASE
    WHEN regexp_like (tc.tags,'pp_fup_iq_acordo')
      OR regexp_like(tc.tags,'iq_fup_iq_acordo')
    THEN True ELSE False
  END AS is_fup_iq_agreement,
  IF(regexp_like (tc.tags,'automacao_ro_resolved_ps_pp_sem_solved'), True, False) AS is_solved_pspp_automation,
  IF(regexp_like(tc.tags,'ticket_migrado_auto_serviço'), True, False) AS is_selfservice_migration,
  IF(regexp_like(tc.tags,'closed_by_merge'), True, False) AS is_closed_by_merge,
  rt.dt_definition,
  rt.dt_chat,
  rt.ts_first_interaction,
  rt.ts_request_created,
  rrc.ts_started,
  rt.ts_initially_assigned_local,
  rt.ts_last_assigned_local,
  to_timestamp(CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data Primeiro FUP Manual Realizado"]') AS STRING),'dd/MM/yy HH') AS ts_measurement,
  to_timestamp(CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data do first reply "]') AS STRING),'dd/MM/yy HH') AS ts_first_reply_milestone,
  to_timestamp(DATEADD(DAY, ROUND(((tc.reply_time_min_calendar/60)/24)),rt.ts_created_local)) AS ts_first_public_comment,
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
  rt.ts_created_local,
  rt.ts_solved_local,
  rt.ts_closed_local,
  tc.ts_updated,
  tc.year,
  tc.month,
  tc.day,
  NOW() AS ts_load
FROM
  datalake_zendesk.tickets_current AS tc
LEFT JOIN
  datalake_repairs.ongoing_repair_tickets AS rt
    ON rt.id_ticket = tc.id_ticket
LEFT JOIN
  repair_request_budget AS b
    ON b.sk_repair_request = rt.id_request
LEFT JOIN
  repair_request_chat AS rrc
    ON rrc.sk_repair_request = rt.id_request
LEFT JOIN
  ticket_events AS te
    ON rt.id_ticket = te.sk_ticket
LEFT JOIN
  status_fup AS sf
    ON sf.id_repair_request = rt.id_request
LEFT JOIN
  ticket_comment_metrics AS tcm
    ON tcm.id_ticket = tc.id_ticket
LEFT JOIN
  tickets_whatsapp AS wpp
    ON wpp.id_contact_ticket = tc.id_ticket
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY rt.id_ticket ORDER BY tc.ts_updated DESC) = 1