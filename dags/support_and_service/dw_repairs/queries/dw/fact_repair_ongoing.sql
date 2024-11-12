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
    CASE
      WHEN REGEXP_LIKE(te.tags,
        'macro_ro_acao_backlog_full_prestador_interno|
        acao_backlog_full_prestador_interno|
        macro_ro_refluxo_tarefa_acionar_parceiro')
      THEN MIN(te.ts_event - INTERVAL 3 HOUR)
    END AS ts_reflux,
    CASE
      WHEN
        REGEXP_LIKE (te.tags,
        'pp_autosserviço_contestou|
        iq_pp_autosserviço_contestou|
        alteração_de_responsabilidade_criticidade|
        acompanhamento_alteracao_responsabilidade_criticidade|
        check_responsabilidade_reparos|
        pp_autosserviço_contestou')
      THEN MIN(te.ts_event - INTERVAL 3 HOUR)
    END AS ts_contestation,
    CASE
      WHEN
        REGEXP_LIKE(te.tags,
        'macro_ro_cont_benfeitoria_pp|
        macro_ro_cont_benfeitoria_iq|
        macro_ro_cont_terceiros_pp|
        macro_ro_cont_terceiros_iq|
        macro_ro_cont_aprovada_iq|
        macro_ro_cont_aprovada_pp|
        macro_ro_cont_reprovada_pp|
        macro_ro_cont_reprovada_iq|
        macro_ro_cont_reprovada_iq|
        closed_by_merge|
        reprovado_ro|
        aprovado_ro|
        opcional_ro|
        ação_backlog_contestação|
        alteração_reprovada|
        alteração_aprovada|
        alteração_benfeitoria')
      THEN MIN(te.ts_event - INTERVAL 3 HOUR)
    END AS ts_resolution_contestation,
    CASE
      WHEN sk_group IN ('11373011255565','10567436267277')
        THEN MIN(te.ts_event - INTERVAL 3 HOUR)
    END AS ts_first_open
  FROM
    dw_customer_support.fact_ticket_events AS te
  WHERE
    te.ts_ticket_created >= DATE('2024-01-01')
  GROUP BY
    te.sk_ticket, te.tags, te.sk_group
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
SELECT
  CAST(rt.id_ticket AS BIGINT) AS sk_ticket,
  COALESCE(rt.id_contact_ticket, -1) AS sk_contact_ticket,
  COALESCE(rt.id_request, -1) AS sk_request,
  COALESCE(rt.id_contract, -1) AS sk_contract,
  COALESCE(tc.id_user_main, -1) AS sk_user,
  COALESCE(MD5(rt.agent_email), -1) AS sk_agent,
  COALESCE(b.id_budget_sender, -1) AS sk_budget_sender,
  COALESCE(CAST(REPLACE(SUBSTRING(rt.ts_first_interaction,1, 10),'-','') AS BIGINT), -1) AS sk_first_interaction_date,
  COALESCE(CAST(REPLACE(SUBSTRING(rt.ts_created_local,1, 10),'-','') AS BIGINT), -1) AS sk_created_local,
  COALESCE(CAST(REPLACE(SUBSTRING(rt.ts_solved_local,1, 10),'-','') AS BIGINT), -1) AS sk_solved_local,
  COALESCE(CAST(REPLACE(SUBSTRING(rt.ts_request_created,1, 10),'-','') AS BIGINT), -1) AS sk_request_created,
  COALESCE(CAST(REPLACE(SUBSTRING(rrc.ts_started,1, 10),'-','') AS BIGINT), -1) AS sk_created_chat,
  COALESCE(CAST(REPLACE(SUBSTRING(rt.ts_updated_local,1, 10),'-','') AS BIGINT), -1) AS sk_updated_local,
  COALESCE(CAST(REPLACE(SUBSTRING(rt.ts_initially_assigned_local,1, 10),'-','') AS BIGINT), -1) AS sk_initially_assigned_local,
  COALESCE(CAST(REPLACE(SUBSTRING(rt.ts_last_assigned_local,1, 10),'-','') AS BIGINT), -1) AS sk_last_assigned_local,
  COALESCE(CAST(REPLACE(SUBSTRING(rt.ts_closed_local,1, 10),'-','') AS BIGINT), -1) AS sk_closed_local,
  COALESCE(CAST(REPLACE(SUBSTRING(to_timestamp(CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data Primeiro FUP Manual Realizado"]') AS STRING),'dd/MM/yy HH'),1, 10),'-','') AS BIGINT), -1) AS sk_measurement,
  COALESCE(CAST(REPLACE(SUBSTRING(to_timestamp(CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data do first reply "]') AS STRING),'dd/MM/yy HH'),1, 10),'-','') AS BIGINT), -1) AS sk_first_reply_milestone,
  COALESCE(CAST(REPLACE(SUBSTRING(DATE(DATEADD(DAY, ROUND(((tc.reply_time_min_calendar/60)/24)),rt.ts_created_local)),1, 10),'-','') AS BIGINT), -1) AS sk_first_public_comment,
  rt.reopens,
  rt.relisting,
  rt.replies,
  IF(rt.has_chat_negociation IS NULL, FALSE, rt.has_chat_negociation) AS has_chat_negociation,
  IF( rt.ts_created_local IS NOT NULL AND rt.ts_solved_local IS NULL , TRUE, FALSE) AS ongoing,
  DATEDIFF(DAY, DATE(rt.ts_created_local) , DATE(rt.ts_solved_local) ) AS frt,
  IF(rt.tags LIKE '%produto_responsabilidade_terceiros%', TRUE, FALSE) AS is_other_responsability,
  DATEDIFF(DAY, rt.ts_created_local, to_timestamp(CAST(GET_JSON_OBJECT(rt.custom_fields, '$["[Data] Data do first reply "]') AS STRING),'dd/MM/yy HH')) AS days_to_first_reply,
  tc.reply_time_min_calendar AS ldt_fr_minutes,
  rt.dt_definition,
  rt.dt_chat,
  te.ts_reflux,
  te.ts_contestation,
  te.ts_resolution_contestation,
  te.ts_first_open,
  sf.ts_help_request,
  NOW() AS ts_load,
  rt.year AS year,
  rt.month AS month,
  rt.day AS day
FROM
  datalake_repairs.repair_tickets AS rt
LEFT JOIN
  datalake_zendesk.tickets_current AS tc
    ON tc.id_ticket = rt.id_ticket
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
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY rt.id_ticket ORDER BY MAKE_DATE(rt.year,rt.month,rt.day) DESC) = 1
