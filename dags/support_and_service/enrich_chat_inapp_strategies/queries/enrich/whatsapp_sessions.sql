WITH pos_list AS (
  SELECT DISTINCT
    CAST(fcp.sk_user AS INTEGER) sk_user,
    fcp.contract_role
  FROM
    dw_public.dim_contract dc
  LEFT JOIN
    dw_quintoandar.fact_contract_people fcp
      ON dc.sk_contract = fcp.sk_contract
  WHERE
	  dc.status = "Ativo"
    AND contract_role IN ("tenant", "dweller")
    AND sk_user != -1
),
--SELECIONA AS SESSOES DE CHAT DO GREENSEER (WHATSAPP e IN_APP)
users_contact AS (
  SELECT DISTINCT
    id_session,
    id_pipeline,
    CAST(COALESCE(id_user, id_user_legacy) AS INTEGER) AS id_user,
    has_chat_inapp_access AS has_chat5a_access,
    strategy AS migration_strategy,
    ts_started
  FROM
    datalake_greenseer.session_memory
  WHERE
    id_pipeline IN ("whatsapp", "whatsapp_main", "whatsapp_main_legacy", "in_app_main")
    AND ts_started >= "2023-01-19"
),
--SELECIONA OS EVENTOS DO AMPLITUDE DISPARADOS NO APLICATIVO
app_events AS (
  SELECT DISTINCT
    id_user,
    ts_event
  FROM
    datalake_app_installed.events
  WHERE
    ts_event >= "2022-10-03"
),
--CONCATENA AS TABELAS | TRAZ SE HOUVE RETENÇÃO | CLASSIFICA SE É ATUALMENTE INQUILINO POS CONTRATO
base_origin AS (
 SELECT DISTINCT
    uc.id_session,
    uc.id_user,
    uc.ts_started,
    uc.has_chat5a_access,
    uc.migration_strategy,
    uc.id_pipeline,
    pl.contract_role,
    gs.is_retention,
    CASE WHEN pl.sk_user IS NOT NULL THEN 1 ELSE 0 END AS currently_tenant_post
  FROM
    users_contact AS uc
  LEFT JOIN
    pos_list pl
      ON pl.sk_user = uc.id_user
  LEFT JOIN
    datalake_greenseer.greenseer_session AS gs
      ON gs.id_session = uc.id_session
),
--CLASSIFICA SE HAVIA APP INSTALADO NO MOMENTO DA SESSAO
base_origin_app AS (
  SELECT DISTINCT
    bo.*,
    CASE WHEN ae.id_user IS NOT NULL THEN 1 ELSE 0 END AS app_installed
  FROM
    base_origin AS bo
  LEFT JOIN
    app_events AS ae
      ON ae.id_user = bo.id_user
      AND DATEDIFF(DATE(bo.ts_started), DATE(ae.ts_event)) BETWEEN 0 AND 90
),
--CSAT/DSAT BOT/ATENDIMENTO HUMANO
csat_dsat_bot AS (
  SELECT
    bo.*,
    csat.grade AS grade_bot,
    csat.comment AS comment_bot,
    zen.id_ticket,
    sa.rating AS grade_human,
    sa.comment AS comment_human,
    sa.is_solved AS is_solved_human
  FROM
    base_origin_app AS bo
  LEFT JOIN
    datalake_chat_fup_clean.rating csat
      ON CAST(csat.id_origin AS INTEGER) = bo.id_session
  LEFT JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics zen
      ON CAST(zen.id_session AS INTEGER) = bo.id_session --ATRAVÉS DO id_session IDENTIFICA O id_ticket NO ZENDESK
  LEFT JOIN
    datalake_chat_fup_clean.chats_chat cc
      ON cc.id_ticket = zen.id_ticket --VIA id_ticket, OBETEM-SE O id DO CHAT
  LEFT JOIN
    datalake_chat_fup_clean.surveys_answer sa
      ON sa.id_survey = cc.id --COM O id ACESSAMOS AS REPOSTAS DO CSAT
),
--STATUS DA SESSAO
--Status da sessão: Cordialidade, Resolvido, Transbordo, Abandono
-- Retenção por cordialidade: sessão classificada como "sem resposta" pelo Jon Snow e o cliente não respondeu ou respondeu que não precisa de ajuda na pergunta de encerramento
-- Respondido sem transbordo: cliente visualizou uma resposta de retenção e não avançou até o atendimento humano
-- Transbordo sem resposta: atendimento por CX com passagem pelo chatbot sem que uma resposta com tentativa de retenção tenha sido exibida
-- Transbordo com resposta: atendimento por CX com passagem pelo chatbot após a exibição de uma resposta com tentativa de retenção
-- Abandono: cliente desistiu do atendimento por conta própria, antes de exibirmos qualquer resposta com tentativa de retenção
base_status AS (
  SELECT DISTINCT
    sm.id_session,
    sm.id_pipeline,
    CAST(sm.jon_snow_with_context AS DOUBLE) AS with_context,
    CAST(sm.jon_snow_no_context AS DOUBLE) AS no_context,
    CAST(sm.jon_snow_greeting AS DOUBLE) AS greeting,
    CAST(sm.jon_snow_no_answer_needed AS DOUBLE) AS no_answer_needed,
    sm.taxonomy AS selected_taxonomy, -- taxonomia referente a resposta enviada
    sm.need_more_help_after_reception AS need_more_help_after_reception, --resposta do cliente para a pergunta se ainda precisa quem falar com a gente,
    sm.tags, -- quando o campo contém "bot_menu_automatic_selection" então disparamos uma resposta automática
    s.source,
    s.ts_created,
    s.status,
    (s.source_environment = "default") AS main_number,
    (s.agent = "QuintoAndar") AS transferred,
    s.ts_updated,
    RANK() OVER (PARTITION BY s.id ORDER BY s.ts_updated DESC) AS r
  FROM
    datalake_greenseer.session_memory AS sm
  LEFT JOIN
    datalake_sauron_clean.session AS s
      ON sm.id_session = s.id
  WHERE
    sm.id_pipeline IN ("in_app_main")
),
classes AS (
  SELECT
    *,
    CASE
      WHEN CAST(need_more_help_after_reception AS STRING) = "true" THEN "precisa de ajuda"
      WHEN CAST(need_more_help_after_reception AS STRING) = "false" THEN "não precisa de ajuda"
      WHEN CAST(need_more_help_after_reception AS STRING) IS NULL THEN "não respondeu"
    END AS resposta_pergunta_encerramento,
    CASE
      WHEN (with_context > no_context AND with_context > greeting AND with_context > no_answer_needed)
        THEN (CASE WHEN (with_context >= 0.5) THEN "context" else "sem_contexto" END)
      WHEN (no_context > with_context AND no_context > greeting AND no_context > no_answer_needed) THEN "sem_contexto"
      WHEN (greeting > no_context AND greeting > with_context AND greeting > no_answer_needed) THEN "saudacao"
      WHEN (no_answer_needed > no_context AND no_answer_needed > with_context AND no_answer_needed > greeting) THEN "sem_resposta"
      ELSE "erro"
    END AS class
  FROM
    base_status
),
base_labels AS (
  SELECT DISTINCT
    gs.id_session,
    CASE
      WHEN class = "sem_resposta" AND resposta_pergunta_encerramento IN ("não precisa de ajuda", "não respondeu")
        THEN "Retenção por cordialidade"
      WHEN is_retention = TRUE THEN "Respondido sem transbordo"
      WHEN selected_taxonomy IS NULL AND main_number = TRUE AND transferred = TRUE AND resposta_pergunta_encerramento IN ("não respondeu")
        THEN "Transbordo sem resposta"
      WHEN selected_taxonomy IS NOT NULL AND main_number = TRUE AND transferred = TRUE THEN "Transbordo após resposta"
      WHEN main_number = TRUE AND selected_taxonomy IS NULL AND transferred = false THEN "Abandono"
      ELSE "Indefinido"
    END AS tag,
    ts_started,
    c.ts_updated
  FROM
    classes AS c
  LEFT JOIN
    datalake_greenseer.greenseer_session AS gs
      ON c.id_session = gs.id_session
  WHERE
    source = "internal_chat"
    AND status = "expired"
    AND (main_number OR transferred) AND r = 1
),
--TAG CHATBOT ADICIONADA
tag_chat AS (
  SELECT
    cdb.*,
    bl.tag,
    bl.ts_updated
  FROM
    csat_dsat_bot AS cdb
  LEFT JOIN
    base_labels AS bl ON bl.id_session = cdb.id_session
),
--ADICIONANDO A CONVERSAO E CRIANDO O MIGRATION_STRATEGY_AJUSTADO
--Devido a possibilidade de um mesmo id_user estar atrelado a duas estratégias (last_open e close), cria-se esse campo ajustado para uma contagem posterior
--de id_user por migration.
ajuste_estrategia AS (
  SELECT
    *,
    CASE
      WHEN
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND id_pipeline = "in_app_main"
      THEN "organic"
      WHEN
        has_chat5a_access IS NULL
        AND id_pipeline IN ("whatsapp", "whatsapp_main", "whatsapp_main_legacy")
        AND migration_strategy IS NULL
      THEN "organic_whatsapp"
      WHEN
        has_chat5a_access IS NOT NULL
        AND ts_started < "2023-02-01"
      THEN "open"
      ELSE migration_strategy
    END AS migration_strategy_adjusted,
    CASE
      WHEN id_pipeline = "in_app_main" THEN "chat5a"
      WHEN id_pipeline IN ("whatsapp", "whatsapp_main", "whatsapp_main_legacy") THEN "whats_principal"
      ELSE NULL
    END AS canal,
    CASE
      WHEN ts_started < "2023-02-01" THEN "pre_estrategia"
        ELSE "pos_estrategia"
    END AS time_estrategia
  FROM
    tag_chat
)
SELECT
  tu.id_session,
  tu.id_user,
  tu.id_pipeline,
  tu.id_ticket,
  tu.migration_strategy,
  tu.migration_strategy_adjusted,
  tu.contract_role,
  tu.tag,
  tu.grade_bot,
  tu.comment_bot,
  tu.grade_human,
  tu.comment_human,
  tu.is_solved_human,
  tu.is_retention,
  tu.app_installed AS has_installed_app,
  tu.has_chat5a_access,
  tu.currently_tenant_post,
  tu.ts_started,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  ajuste_estrategia AS tu
WHERE
    YEAR(ts_started) = {year}
    AND MONTH(ts_started) = {month}
    AND DAY(ts_started) = {day}
