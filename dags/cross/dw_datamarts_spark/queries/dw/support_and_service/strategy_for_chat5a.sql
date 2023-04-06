WITH pos_list AS (
  SELECT DISTINCT
    CAST(fcp.sk_user AS integer) sk_user,
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
    ts_started,
    CAST(COALESCE(
          GET_JSON_OBJECT(memory, '$.legacy.user_data.user.id'),
          GET_JSON_OBJECT(memory, '$.basic.user.id')
        ) AS integer) AS id_user,
    CAST(GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.has_access') AS boolean) AS has_chat5a_access,
    CAST(GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.whatsapp_strategy') AS string) AS migration_strategy,
    id_pipeline
  FROM
    datalake_greenseer_clean.session ss
  WHERE
    id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy', 'in_app_main')
    AND DATE(ts_started) >= DATE('2023-01-19')
    AND DATE(ts_started) <= DATE(current_date)
),
--SELECIONA OS ID_USER COM ACESSO AO CHAT E CONTA EM QUANTAS ESTRATÉGIAS DIFERENTES ELE CAIU
fix_count_strategy AS (
  SELECT
    CAST(COALESCE(
          GET_JSON_OBJECT(memory, '$.legacy.user_data.user.id'),
          GET_JSON_OBJECT(memory, '$.basic.user.id')
      ) AS integer) AS id_user,
    COUNT(DISTINCT CAST(GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.whatsapp_strategy') AS string)) total_strategy
  FROM datalake_greenseer_clean.session ss
  WHERE
    CAST(GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.has_access') AS boolean) = true
    AND DATE(ts_started) >= DATE('2023-01-19')
    AND DATE(ts_started) <= DATE(current_date)
  GROUP BY 1
),
base_origin AS (
  SELECT DISTINCT
    uc.id_session,
    uc.id_user,
    uc.ts_started,
    ROW_NUMBER() OVER(PARTITION BY uc.id_user ORDER BY uc.ts_started ASC) AS session_ordem,
    uc.has_chat5a_access,
    uc.migration_strategy,
    fcs.total_strategy,
    uc.id_pipeline,
    pl.contract_role,
    gs.is_retention
  FROM
    users_contact uc
  INNER JOIN
    pos_list pl
      ON pl.sk_user = uc.id_user
  LEFT JOIN
    datalake_greenseer.greenseer_session gs
      ON gs.id_session = uc.id_session
  LEFT JOIN
    fix_count_strategy fcs
      ON fcs.id_user = uc.id_user
),
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
    base_origin bo
  LEFT JOIN
    datalake_chat_fup_clean.rating csat
      ON CAST(csat.id_origin AS integer) = bo.id_session
  LEFT JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics zen
      ON CAST(zen.id_session AS integer) = bo.id_session --ATRAVÉS DO id_session IDENTIFICA O id_ticket NO ZENDESK
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
      id_session,
      CAST(GET_JSON_OBJECT(memory, '$.predictions.jon_snow.with_context') AS double) AS with_context,
      CAST(GET_JSON_OBJECT(memory, '$.predictions.jon_snow.no_context') AS double) AS no_context,
      CAST(GET_JSON_OBJECT(memory, '$.predictions.jon_snow.greeting') AS double) AS greeting,
      CAST(GET_JSON_OBJECT(memory, '$.predictions.jon_snow.no_answer_needed') AS double) AS no_answer_needed,
      GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.selected_taxonomy') AS selected_taxonomy, -- taxonomia referente a resposta enviada
      GET_JSON_OBJECT(memory, '$.business_rules.more_help_required.after_reception.value') AS need_more_help_after_reception, --resposta do cliente para a pergunta se ainda precisa quem falar com a gente,
      GET_JSON_OBJECT(memory, '$.business_rules.tags.added') AS tags, -- quando o campo contém 'bot_menu_automatic_selection' então disparamos uma resposta automática
      s.source,
      s.ts_created,
      s.status,
      (s.source_environment = 'default') AS main_number,
      (s.agent = 'QuintoAndar') AS transferred,
      rank() over (partition by s.id order by s.ts_updated desc) AS r,
      id_pipeline
  FROM
      datalake_greenseer_clean.session AS gs
  LEFT JOIN
    datalake_sauron_clean.session AS s
      ON gs.id_session = s.id
  WHERE
    id_pipeline IN ('in_app_main')
),
classes AS (
  SELECT
    *,
    CASE WHEN CAST(need_more_help_after_reception AS string) = 'true' THEN 'precisa de ajuda'
         WHEN CAST(need_more_help_after_reception AS string) = 'false' THEN 'não precisa de ajuda'
         WHEN CAST(need_more_help_after_reception AS string) IS NULL THEN 'não respondeu'
    END AS resposta_pergunta_encerramento,
    CASE
        WHEN (with_context > no_context AND with_context > greeting AND with_context > no_answer_needed) then
            (CASE WHEN (with_context >= 0.5) THEN 'context' else 'sem_contexto' end)
        WHEN (no_context > with_context AND no_context > greeting AND no_context > no_answer_needed) THEN 'sem_contexto'
        WHEN (greeting > no_context AND greeting > with_context AND greeting > no_answer_needed) THEN 'saudacao'
        WHEN (no_answer_needed > no_context AND no_answer_needed > with_context AND no_answer_needed > greeting) THEN 'sem_resposta'
        else 'erro'
    END AS class
  FROM base_status
),
base_labels AS (
  SELECT DISTINCT
    gs.id_session,
    ts_started,
    CASE
      WHEN class = 'sem_resposta' AND resposta_pergunta_encerramento IN ('não precisa de ajuda', 'não respondeu') THEN 'Retenção por cordialidade'
      WHEN is_retention = true THEN 'Respondido sem transbordo'
      WHEN selected_taxonomy IS NULL AND main_number = true AND transferred = true AND resposta_pergunta_encerramento IN ('não respondeu') THEN 'Transbordo sem resposta'
      WHEN selected_taxonomy IS NOT NULL AND main_number = true AND transferred = true THEN 'Transbordo após resposta'
      WHEN main_number = true AND selected_taxonomy IS NULL AND transferred = false THEN 'Abandono'
      ELSE 'Indefinido'
    END AS tag
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
    csat_dsat_bot cdb
  LEFT JOIN
    base_labels bl
      ON bl.id_session = cdb.id_session
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
    CAST(trim('.' FROM id_user) AS integer) id_user_inst,
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
      ELSE NULL END AS has_installed_app
  FROM
    tag_chat tc
  LEFT JOIN
    tem_app ta
      ON ta.id_user_inst = tc.id_user
),
--VALIDADOR DE ESTRATEGIAS, EM QUANTAS ESTRATEGIAS AS PESSOAS ESTAO
quais_estrategias AS (
  SELECT
    id_user,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'last_open' THEN id_user end) AS last_open,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'close' THEN id_user end) AS close,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'suggest' THEN id_user end) AS suggest,
    COUNT(DISTINCT CASE WHEN migration_strategy = 'open' THEN id_user end) AS open,
    COUNT(DISTINCT migration_strategy) total_estrategias
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
      WHEN  last_open = 1 and
            close = 1 AND
            close = 1 AND
            suggest = 1 THEN 'last_open + close + open + suggest'
      WHEN  last_open = 1 and
            close = 1 AND
            close = 1 AND
            suggest = 0 THEN 'last_open + close + open'
      WHEN  last_open = 1 and
            close = 1 AND
            close = 0 AND
            suggest = 1 THEN 'last_open + close + suggest'
      WHEN  last_open = 1 and
            close = 1 AND
            close = 0 AND
            suggest = 1 THEN 'last_open + open + suggest'
      WHEN  last_open = 0 and
            close = 1 AND
            close = 1 AND
            suggest = 1 THEN 'close + open + suggest'
      WHEN last_open = 1 AND
            close = 1 and
            close = 0 AND
            suggest = 0 THEN 'last_open + close'
      WHEN last_open = 1 AND
            close = 0 and
            close = 1 AND
            suggest = 0 THEN 'last_open + open'
      WHEN last_open = 0 AND
            close = 1 and
            close = 1 AND
            suggest = 0 THEN 'close + open'
      WHEN last_open = 0 AND
            close = 0 and
            close = 1 AND
            suggest = 1 THEN 'suggest + open'
      WHEN  last_open = 1 AND
            close = 0 and
            close = 0 AND
            suggest = 1 THEN 'last_open + suggest'
      WHEN  last_open = 0 AND
            close = 1 and
            close = 0 AND
            suggest = 1 THEN 'suggest + close'
      WHEN  last_open = 1 AND
            close = 0 and
            close = 0 AND
            suggest = 0 THEN 'last_open'
      WHEN  last_open = 0 AND
            close = 1 and
            close = 0 AND
            suggest = 0 THEN 'close'
      WHEN  last_open = 0 AND
            close = 0 and
            close = 1 AND
            suggest = 0 THEN 'open'
      WHEN  last_open = 0 AND
            close = 0 and
            close = 0 AND
            suggest = 1 THEN 'suggest'
      ELSE NULL END AS marcador_mais_estrategia
  FROM quais_estrategias
),
com_contador_estrategias AS (
  SELECT
    ai.*,
    qme.marcador_mais_estrategia
  FROM
    app_instalado ai
  LEFT JOIN
    quantificador_mais_estrategias qme
      ON qme.id_user = ai.id_user
),
--ADICIONANDO A CONVERSAO E CRIANDO O MIGRATION_STRATEGY_AJUSTADO
--Devido a possibilidade de um mesmo id_user estar atrelado a duas estratégias (last_open e close), cria-se esse campo ajustado para uma contagem posterior
--de id_user por migration.
ajuste_estrategia AS (
  SELECT
  *,
  CASE
	WHEN has_chat5a_access IS NULL and
	 	 total_strategy IS NULL and
	 	 id_pipeline = 'in_app_main' and
	 	 marcador_mais_estrategia IS NULL and
	 	 DATE(ts_started) >= DATE('2023-02-01') and
	 	 migration_strategy IS NULL
	THEN 'organic'
	WHEN has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'open'
		 or
		 DATE(ts_started) < DATE('2023-02-01')
	THEN 'open'
	WHEN has_chat5a_access IS NULL and
	 	 total_strategy IS NULL and
	 	 id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy') and
	 	 marcador_mais_estrategia IS NULL and
	 	 migration_strategy IS NULL
	THEN 'organic_whatsapp'
	WHEN has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'suggest'
		 or
		 has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'suggest + open'
	THEN 'suggest'
	WHEN has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'close'
		 or
	     has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'close + open'
		 or
	     has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'last_open + close + open'
		 or
	     has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'last_open + close'
		 or
	     has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'last_open + close + open + suggest'
	THEN 'close'
	WHEN has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'last_open'
		 or
	     has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'last_open + open'
		 or
	     has_chat5a_access IS NULL and
		 migration_strategy IS NULL and
		 total_strategy IS NOT NULL and
		 id_pipeline = 'in_app_main' and
		 DATE(ts_started) >= DATE('2023-02-01') and
		 marcador_mais_estrategia = 'last_open + suggest'
	THEN 'last_open'

	WHEN has_chat5a_access IS NOT NULL
    	then
    		case
            WHEN DATE(ts_started) < DATE('2023-02-01') THEN 'open'
            else
            CASE
                    WHEN migration_strategy = 'suggest' AND
                        marcador_mais_estrategia = 'suggest'
                        or
                        migration_strategy = 'suggest' AND
                        marcador_mais_estrategia = 'suggest + open'
                        or
                        migration_strategy = 'open' and
                        marcador_mais_estrategia = 'suggest + open'
                        or
                        migration_strategy IS NULL and
                        marcador_mais_estrategia = 'suggest' and
                        total_strategy IS NOT NULL
                    THEN 'suggest'
                    WHEN migration_strategy = 'open' AND
                        marcador_mais_estrategia = 'open'
                    THEN 'open'

                    WHEN migration_strategy = 'close' AND
                        marcador_mais_estrategia = 'close'
                        or
                        migration_strategy = 'close' AND
                        marcador_mais_estrategia = 'close + open'
                        or
                        migration_strategy = 'open' and
                        marcador_mais_estrategia = 'close + open'
                        or
                        migration_strategy = 'last_open' and
                        marcador_mais_estrategia = 'last_open + close + open'
                        or
                        migration_strategy = 'close' and
                        marcador_mais_estrategia = 'last_open + close + open'
                        or
                        migration_strategy = 'open' and
                        marcador_mais_estrategia = 'last_open + close + open'
                        or
                        migration_strategy = 'last_open' and
                        marcador_mais_estrategia = 'last_open + close'
                        or
                        migration_strategy = 'close' and
                        marcador_mais_estrategia = 'last_open + close'
                        or
          migration_strategy = 'close' and
                        marcador_mais_estrategia = 'last_open + close + open + suggest'
                        or
          migration_strategy = 'last_open' and
                        marcador_mais_estrategia = 'last_open + close + open + suggest'
                        or
          migration_strategy = 'open' and
                        marcador_mais_estrategia = 'last_open + close + open + suggest'
                        or
          migration_strategy = 'suggest' and
                        marcador_mais_estrategia = 'last_open + close + open + suggest'
                    THEN 'close'

                    WHEN migration_strategy = 'last_open' AND
                        marcador_mais_estrategia = 'last_open'
                        or
                        migration_strategy = 'last_open' and
                        marcador_mais_estrategia = 'last_open + open'
                        or
                        migration_strategy = 'open' and
                        marcador_mais_estrategia = 'last_open + open'
                        or
                        migration_strategy = 'last_open' and
                        marcador_mais_estrategia = 'last_open + suggest'
                        or
                        migration_strategy = 'suggest' and
                        marcador_mais_estrategia = 'last_open + suggest'
                    THEN 'last_open'
                    ELSE NULL
                  end
            end
	END AS migration_strategy_adjusted,
	case
        WHEN id_pipeline = 'in_app_main' THEN 'chat5a'
        WHEN id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy') THEN 'whats_principal'
       ELSE NULL
    END AS canal,
    CASE
        WHEN DATE(ts_started) < DATE('2023-02-01') THEN 'pre_estrategia'
       else 'pos_estrategia'
    END AS time_estrategia
FROM com_contador_estrategias
),
tags_users AS (
  SELECT
    id_session,
    id_user,
    ts_started,
    session_ordem,
    has_chat5a_access,
    migration_strategy,
    total_strategy,
    id_pipeline,
    contract_role,
    is_retention,
    tag,
    grade_bot,
    comment_bot,
    grade_human,
    comment_human,
    is_solved_human,
    has_installed_app,
    marcador_mais_estrategia,
    id_ticket,
    migration_strategy_adjusted,
    CASE
      WHEN migration_strategy_adjusted IN ('suggest','open','last_open') AND
        has_chat5a_access = true and
        lead(id_pipeline) over (partition by id_user order by ts_started asc) = 'in_app_main' AND
        lead(session_ordem) over (partition by id_user order by ts_started asc) = session_ordem + 1
      THEN 'sim'
      WHEN migration_strategy_adjusted = 'close' AND
        has_chat5a_access = true and
        lead(id_pipeline) over (partition by id_user order by ts_started asc) = 'in_app_main' and
        lead(session_ordem) over (partition by id_user order by ts_started asc) = session_ordem + 1
       THEN 'sim'
       WHEN has_chat5a_access IS NULL and
          migration_strategy IS NULL and
          total_strategy IS NULL and
          id_pipeline = 'in_app_main' THEN 'sim'
        ELSE NULL END AS houve_conversao
  FROM ajuste_estrategia
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
  tu.has_installed_app,
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
  tags_users tu
LEFT JOIN
  datalake_customer_support.chat atc
    ON tu.id_ticket = atc.id_ticket
