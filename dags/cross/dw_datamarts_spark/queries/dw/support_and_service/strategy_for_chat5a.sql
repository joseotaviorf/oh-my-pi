---------SELECAO DE USER COM CONTRATO ATIVO, INQUILINO/MORADOR
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
	  dc.status = 'Ativo'
    AND contract_role IN ('tenant', 'dweller')
    AND sk_user <> -1
),
--SELECIONA OS USERS QUE ENTRARAM EM CONTATO NO NÚMERO PRINCIPAL
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
    id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy', 'in_app_main')
    AND DATE(ts_started) >= DATE('2023-01-19')
    AND DATE(ts_started) <= DATE(CURRENT_DATE())
),
--SELECIONA OS ID_USER COM ACESSO AO CHAT E CONTA EM QUANTAS ESTRATÉGIAS DIFERENTES ELE CAIU
fix_count_strategy AS (
  SELECT
    CAST(COALESCE(id_user, id_user_legacy) AS INTEGER) AS id_user,
    COUNT(DISTINCT(CAST(strategy AS STRING))) total_strategy
  FROM
    datalake_greenseer.session_memory
  WHERE
    has_chat_inapp_access IS NOT NULL
    AND DATE(ts_started) >= DATE('2023-01-19')
    AND DATE(ts_started) <= DATE(CURRENT_DATE())
  GROUP BY 1
),
fix_count_strategy_2 AS (
  SELECT
    CAST(COALESCE(id_user, id_user_legacy) AS INTEGER) AS id_user,
    COUNT(DISTINCT(CAST(strategy AS STRING)) IS NOT NULL) total_strategy_2
  FROM
    datalake_greenseer.session_memory
  WHERE
    has_chat_inapp_access IS NOT NULL
    AND DATE(ts_started) >= DATE('2023-04-01')
    AND DATE(ts_started) <= DATE(CURRENT_DATE())
  GROUP BY 1
),
--CONCATENA AS TABELAS E ATRIBUI UMA ORDEM PARA A CRIAÇÃO DE SESSÕES, FILTRA POR id_user AQUELES QUE SÃO IQ_PÓS E TRAZ SE HOUVE RETENÇÃO
base_origin AS (
 SELECT DISTINCT
    uc.id_session,
    uc.id_user,
    uc.ts_started,
    ROW_NUMBER() OVER(PARTITION BY uc.id_user ORDER BY uc.ts_started ASC) AS session_ordem,
    uc.has_chat5a_access,
    uc.migration_strategy,
    fcs.total_strategy,
    fcs2.total_strategy_2,
    uc.id_pipeline,
    pl.contract_role,
    gs.is_retention
  FROM
    users_contact AS uc
  INNER JOIN
    pos_list pl
      ON pl.sk_user = uc.id_user
  LEFT JOIN
    datalake_greenseer.greenseer_session gs
      ON gs.id_session = uc.id_session
  LEFT JOIN
    fix_count_strategy fcs
      ON fcs.id_user = uc.id_user
  LEFT JOIN
    fix_count_strategy_2 fcs2
      ON fcs2.id_user = uc.id_user
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
    base_origin AS bo
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
    sm.tags, -- quando o campo contém 'bot_menu_automatic_SELECTion' então disparamos uma resposta automática
    s.source,
    s.ts_created,
    s.status,
    (s.source_environment = 'default') AS main_number,
    (s.agent = 'QuintoAndar') AS transferred,
    RANK() OVER (PARTITION BY s.id ORDER BY s.ts_updated DESC) AS r
  FROM
    datalake_greenseer.session_memory AS sm
  LEFT JOIN
    datalake_sauron_clean.session AS s
      ON sm.id_session = s.id
  WHERE
    id_pipeline IN ('in_app_main')
),
classes AS (
  SELECT
    *,
    CASE
      WHEN CAST(need_more_help_after_reception AS STRING) = 'true' THEN 'precisa de ajuda'
      WHEN CAST(need_more_help_after_reception AS STRING) = 'false' THEN 'não precisa de ajuda'
      WHEN CAST(need_more_help_after_reception AS STRING) IS NULL THEN 'não respondeu'
    END AS resposta_pergunta_encerramento,
    CASE
      WHEN (with_context > no_context AND with_context > greeting AND with_context > no_answer_needed)
        THEN (CASE WHEN (with_context >= 0.5) THEN 'context' else 'sem_contexto' END)
      WHEN (no_context > with_context AND no_context > greeting AND no_context > no_answer_needed) THEN 'sem_contexto'
      WHEN (greeting > no_context AND greeting > with_context AND greeting > no_answer_needed) THEN 'saudacao'
      WHEN (no_answer_needed > no_context AND no_answer_needed > with_context AND no_answer_needed > greeting) THEN 'sem_resposta'
      ELSE 'erro'
    END AS class
  FROM
    base_status
),
base_labels AS (
  SELECT DISTINCT
    gs.id_session,
    CASE
      WHEN class = 'sem_resposta' AND resposta_pergunta_encerramento IN ('não precisa de ajuda', 'não respondeu')
        THEN 'Retenção por cordialidade'
      WHEN is_retention = TRUE THEN 'Respondido sem transbordo'
      WHEN selected_taxonomy IS NULL AND main_number = TRUE AND transferred = TRUE AND resposta_pergunta_encerramento IN ('não respondeu')
        THEN 'Transbordo sem resposta'
      WHEN selected_taxonomy IS NOT NULL AND main_number = TRUE AND transferred = TRUE THEN 'Transbordo após resposta'
      WHEN main_number = TRUE AND selected_taxonomy IS NULL AND transferred = false THEN 'Abandono'
      ELSE 'Indefinido'
    END AS tag,
    ts_started
  FROM
    classes AS c
  LEFT JOIN
    datalake_greenseer.greenseer_session AS gs
      ON c.id_session = gs.id_session
  WHERE
    source = 'internal_chat'
    AND status = 'expired'
    AND (main_number or transferred) AND r = 1
),
--TAG CHATBOT ADICIONADA
tag_chat AS (
  SELECT
    cdb.*,
    bl.tag
  FROM
    csat_dsat_bot AS cdb
  LEFT JOIN
    base_labels as bl on bl.id_session = cdb.id_session
),
--ADICIONANDO EVENTO TER APP
events_platform AS (
  SELECT DISTINCT
    id_user,
    ts_event,
    platform
  FROM
    datalake_amplitude_clean.events AS evt
  LEFT JOIN
    datalake_amplitude_clean.170698_user_merge mrg
      ON mrg.id_amplitude = evt.id_amplitude
  WHERE
    DATE(evt.ts_event) >= DATE('2023-03-20') - interval '90' day AND DATE(evt.ts_event) <= DATE('2023-03-20')
    AND evt.id_app = 170698
    AND platform IN ('Android','iOS')
    AND id_user <> 'userId'
),
events_platform_clean AS (
   SELECT
     CAST(trim('.' FROM id_user) AS INTEGER) id_user_inst,
     ts_event,
     platform
  FROM
    events_platform
),
tem_app AS (
  SELECT
    id_user_inst,
    COUNT(DISTINCT platform) total_plataformas
  FROM
    events_platform_clean
  WHERE
    platform IS NOT NULL
    AND length(platform) > 2
GROUP BY 1
),
app_instalado AS (
  SELECT
    tc.*,
    CASE
      WHEN total_plataformas >= 1 THEN 'tem_app'
      WHEN total_plataformas IS NULL THEN 'sem_app'
      ELSE NULL
    END AS app_instalado
  FROM
    tag_chat tc
  LEFT JOIN
    tem_app AS ta
      ON ta.id_user_inst = tc.id_user
),
--VALIDADOR DE ESTRATEGIAS, EM QUANTAS ESTRATEGIAS AS PESSOAS ESTAO
quais_estrategias AS (
  SELECT
    id_user,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'last_open' AND DATE(ts_started) < DATE('2023-04-01') THEN id_user END) last_open_1,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'close' AND DATE(ts_started) < DATE('2023-04-01') THEN id_user END) close_1,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'suggest' AND DATE(ts_started) < DATE('2023-04-01') THEN id_user END) suggest_1,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'open' AND DATE(ts_started) < DATE('2023-04-01') THEN id_user END) open_1,
    COUNT(DISTINCT CASE WHEN migration_strategy IS NOT NULL AND DATE(ts_started) < DATE('2023-04-01') THEN migration_strategy END) total_estrategias_1,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'last_open' AND DATE(ts_started) >= DATE('2023-04-01') THEN id_user END) last_open_2,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'close' AND DATE(ts_started) >= DATE('2023-04-01') THEN id_user END) close_2,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'suggest' AND DATE(ts_started) >= DATE('2023-04-01') THEN id_user END) suggest_2,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'open' AND DATE(ts_started) >= DATE('2023-04-01') THEN id_user END) open_2,
    COUNT(DISTINCT CASE WHEN migration_strategy IS NOT NULL AND DATE(ts_started) >= DATE('2023-04-01') THEN migration_strategy END) total_estrategias_2
  FROM
    app_instalado
  WHERE
    has_chat5a_access IS NOT NULL
  GROUP BY 1
),
quantificador_mais_estrategias AS (
  SELECT
    id_user,
    CASE
      WHEN last_open_1 = 1 AND close_1 = 0 AND open_1 = 0 AND suggest_1 = 0 THEN 'last_open'
      WHEN last_open_1 = 1 AND close_1 = 1 AND open_1 = 1 AND suggest_1 = 1 THEN 'last_open + close + open + suggest'
      WHEN last_open_1 = 1 AND close_1 = 1 AND open_1 = 1 AND suggest_1 = 0 THEN 'last_open + close + open'
      WHEN last_open_1 = 1 AND close_1 = 1 AND open_1 = 0 AND suggest_1 = 1 THEN 'last_open + close + suggest'
      WHEN last_open_1 = 1 AND close_1 = 1 AND open_1 = 0 AND suggest_1 = 1 THEN 'last_open + open + suggest'
      WHEN last_open_1 = 1 AND close_1 = 1 AND open_1 = 0 AND suggest_1 = 0 THEN 'last_open + close'
      WHEN last_open_1 = 1 AND close_1 = 0 AND open_1 = 1 AND suggest_1 = 0 THEN 'last_open + open'
      WHEN last_open_1 = 1 AND close_1 = 0 AND open_1 = 0 AND suggest_1 = 1 THEN 'last_open + suggest'
      WHEN last_open_1 = 0 AND close_1 = 1 AND open_1 = 0 AND suggest_1 = 0 THEN 'close'
      WHEN last_open_1 = 0 AND close_1 = 1 AND open_1 = 1 AND suggest_1 = 0 THEN 'close + open'
      WHEN last_open_1 = 0 AND close_1 = 1 AND open_1 = 1 AND suggest_1 = 1 THEN 'close + open + suggest'
      WHEN last_open_1 = 0 AND close_1 = 1 AND open_1 = 0 AND suggest_1 = 1 THEN 'suggest + close'
      WHEN last_open_1 = 0 AND close_1 = 0 AND open_1 = 1 AND suggest_1 = 1 THEN 'suggest + open'
      WHEN  last_open_1 = 0 AND close_1 = 0 AND open_1 = 0 AND suggest_1 = 1 THEN 'suggest'
      WHEN  last_open_1 = 0 AND close_1 = 0 AND open_1 = 1 AND suggest_1 = 0 THEN 'open'
      ELSE NULL
    END AS marcador_mais_estrategia,
    CASE
      WHEN last_open_2 = 0 AND close_2 = 0 AND open_2= 1 AND suggest_2 = 0 THEN 'open'
      WHEN  last_open_2 = 0 AND close_2 = 0 AND open_2 = 0 AND suggest_2 = 1 THEN 'suggest'
      WHEN last_open_2 = 0 AND close_2 = 0 AND open_2 = 1 AND suggest_2 = 1 THEN 'suggest + open'
      ELSE NULL
    END AS marcador_mais_estrategia_2
  FROM
    quais_estrategias
),
com_contador_estrategias AS (
  SELECT
    ai.*,
    qme.marcador_mais_estrategia,
    qme.marcador_mais_estrategia_2
  FROM
    app_instalado AS ai
  LEFT JOIN
    quantificador_mais_estrategias qme
      on qme.id_user = ai.id_user
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
        AND total_strategy IS NULL
        AND marcador_mais_estrategia IS NULL
        AND migration_strategy IS NULL
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND id_pipeline = 'in_app_main'
        OR --regra de apoio a estrategia adotada em abril/23
        has_chat5a_access IS NULL
        AND total_strategy_2 IS NULL
        AND marcador_mais_estrategia_2 IS NULL
        AND migration_strategy IS NULL
        AND DATE(ts_started) >= DATE('2023-04-01')
        AND id_pipeline = 'in_app_main'
        OR
        has_chat5a_access IS NULL
        AND total_strategy IS NOT NULL
        AND total_strategy_2 IS NOT NULL
        AND marcador_mais_estrategia_2 IS NOT NULL
        AND marcador_mais_estrategia IS NULL
        AND migration_strategy IS NULL
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND id_pipeline = 'in_app_main'
      THEN 'organic'
      WHEN
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND marcador_mais_estrategia = 'open'
        AND total_strategy IS NOT NULL
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND id_pipeline = 'in_app_main'
        OR
        DATE(ts_started) < DATE('2023-02-01')
        OR --regra de apoio a estrategia adotada em abril/23
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND marcador_mais_estrategia_2 = 'open'
        AND total_strategy IS NOT NULL
        AND DATE(ts_started) >= DATE('2023-04-01')
        AND id_pipeline = 'in_app_main'
      THEN 'open'
      WHEN
        has_chat5a_access IS NULL
        AND total_strategy IS NULL
        AND id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy')
        AND marcador_mais_estrategia IS NULL
        AND migration_strategy IS NULL
      THEN 'organic_whatsapp'
      WHEN
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND marcador_mais_estrategia = 'suggest'
        OR
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND marcador_mais_estrategia = 'suggest + open'
        OR --regra de apoio a estrategia adotada em abril/23
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-04-01')
        AND marcador_mais_estrategia_2 = 'suggest'
        OR
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-04-01')
        AND marcador_mais_estrategia_2 = 'suggest + open'
      THEN 'suggest'
      WHEN
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND marcador_mais_estrategia = 'close'
        OR
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND marcador_mais_estrategia = 'close + open'
        OR
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND marcador_mais_estrategia = 'last_open + close + open'
        OR
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND marcador_mais_estrategia = 'last_open + close'
        OR
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND marcador_mais_estrategia = 'last_open + close + open + suggest'
      THEN 'close'
      WHEN
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND marcador_mais_estrategia = 'last_open'
        OR
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND marcador_mais_estrategia = 'last_open + open'
        OR
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND total_strategy IS NOT NULL
        AND id_pipeline = 'in_app_main'
        AND DATE(ts_started) >= DATE('2023-02-01')
        AND DATE(ts_started) < DATE('2023-04-01')
        AND marcador_mais_estrategia = 'last_open + suggest'
      THEN 'last_open'
      WHEN has_chat5a_access IS NOT NULL
        THEN
          CASE
            WHEN DATE(ts_started) < DATE('2023-02-01') THEN 'open'
            ELSE
              CASE
                WHEN
                  migration_strategy = 'suggest'
                  AND marcador_mais_estrategia = 'suggest'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'suggest'
                  AND marcador_mais_estrategia = 'suggest + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'open'
                  AND marcador_mais_estrategia = 'suggest + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy IS NULL
                  AND marcador_mais_estrategia = 'suggest'
                  AND total_strategy IS NOT NULL
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR --regra de apoio a estrategia adotada em abril/23
                  migration_strategy = 'suggest'
                  AND marcador_mais_estrategia_2 = 'suggest'
                  AND DATE(ts_started) >= DATE('2023-04-01')
                  OR
                  migration_strategy = 'suggest'
                  AND marcador_mais_estrategia_2 = 'suggest + open'
                  AND DATE(ts_started) >= DATE('2023-04-01')
                  OR
                  migration_strategy = 'open'
                  AND marcador_mais_estrategia_2 = 'suggest + open'
                  AND DATE(ts_started) >= DATE('2023-04-01')
                  OR migration_strategy IS NULL
                  AND marcador_mais_estrategia_2 = 'suggest'
                  AND DATE(ts_started) >= DATE('2023-04-01')
                  AND total_strategy IS NOT NULL
                THEN 'suggest'
                WHEN
                  migration_strategy = 'open'
                  AND marcador_mais_estrategia = 'open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR --regra de apoio a estrategia adotada em abril/23
                  migration_strategy = 'open'
                  AND marcador_mais_estrategia_2 = 'open'
                  AND DATE(ts_started) >= DATE('2023-04-01')
                THEN 'open'
                WHEN
                  migration_strategy = 'close'
                  AND marcador_mais_estrategia = 'close'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'close'
                  AND marcador_mais_estrategia = 'close + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'open'
                  AND marcador_mais_estrategia = 'close + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'last_open'
                  AND marcador_mais_estrategia = 'last_open + close + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'close'
                  AND marcador_mais_estrategia = 'last_open + close + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'open'
                  AND marcador_mais_estrategia = 'last_open + close + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'last_open'
                  AND marcador_mais_estrategia = 'last_open + close'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'close'
                  AND marcador_mais_estrategia = 'last_open + close'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'close'
                  AND marcador_mais_estrategia = 'last_open + close + open + suggest'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'last_open'
                  AND marcador_mais_estrategia = 'last_open + close + open + suggest'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'open'
                  AND marcador_mais_estrategia = 'last_open + close + open + suggest'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'suggest'
                  AND marcador_mais_estrategia = 'last_open + close + open + suggest'
                  AND DATE(ts_started) < DATE('2023-04-01')
                THEN 'close'
                WHEN
                  migration_strategy = 'last_open'
                  AND marcador_mais_estrategia = 'last_open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'last_open'
                  AND marcador_mais_estrategia = 'last_open + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'open'
                  AND marcador_mais_estrategia = 'last_open + open'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'last_open'
                  AND marcador_mais_estrategia = 'last_open + suggest'
                  AND DATE(ts_started) < DATE('2023-04-01')
                  OR
                  migration_strategy = 'suggest'
                  AND marcador_mais_estrategia = 'last_open + suggest'
                  AND DATE(ts_started) < DATE('2023-04-01')
                THEN 'last_open'
                ELSE NULL
              END
          END
    END AS migration_strategy_adjusted,
    CASE
      WHEN id_pipeline = 'in_app_main' THEN 'chat5a'
      WHEN id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy') THEN 'whats_principal'
      ELSE NULL
    END AS canal,
    CASE
      WHEN DATE(ts_started) < DATE('2023-02-01') THEN 'pre_estrategia'
        ELSE 'pos_estrategia'
    END AS time_estrategia
  FROM
    com_contador_estrategias
),
tabela_conversao AS (
  SELECT
    *,
    CASE
      WHEN
        migration_strategy_adjusted IN ('suggest','open','last_open')
        AND has_chat5a_access IS TRUE
        AND LEAD(id_pipeline) OVER (PARTITION BY id_user ORDER BY ts_started ASC) = 'in_app_main'
        AND LEAD(session_ordem) OVER (PARTITION BY id_user ORDER BY ts_started ASC) = session_ordem + 1
      THEN 'sim'
      WHEN
        migration_strategy_adjusted = 'close'
        AND has_chat5a_access = TRUE
        AND LEAD(id_pipeline) OVER (PARTITION BY id_user ORDER BY ts_started ASC) = 'in_app_main'
        AND LEAD(session_ordem) OVER (PARTITION BY id_user ORDER BY ts_started ASC) = session_ordem + 1
      THEN 'sim'
      WHEN
        has_chat5a_access IS NULL
        AND migration_strategy IS NULL
        AND migration_strategy_adjusted IN ('organic')
        AND id_pipeline = 'in_app_main' THEN 'sim'
      ELSE NULL
    END AS houve_conversao
  FROM
    ajuste_estrategia
)
SELECT
  tu.id_session,
  tu.id_user,
  tu.id_pipeline,
  atc.id_conversation,
  tu.id_ticket,
  atc.id_segment,
  tu.session_ordem,
  tu.has_chat5a_access,
  tu.migration_strategy,
  tu.total_strategy,
  tu.migration_strategy_adjusted,
  tu.contract_role,
  tu.is_retention,
  tu.tag,
  tu.houve_conversao,
  tu.grade_bot,
  tu.comment_bot,
  tu.grade_human,
  tu.comment_human,
  tu.is_solved_human,
  tu.app_instalado AS has_installed_app,
  atc.ticket_origin,
  atc.is_solved,
  atc.completion_reason,
  atc.department,
  atc.seconds_first_reply,
  atc.total_minutes_queue_time,
  atc.total_minutes_talk_time,
  atc.total_minutes_wrap_up_time,
  atc.total_minutes_handling_time,
  tu.ts_started,
  atc.ts_ticket_started
FROM
  tabela_conversao AS tu
LEFT JOIN
  datalake_customer_support.chat atc
    ON tu.id_ticket = atc.id_ticket
