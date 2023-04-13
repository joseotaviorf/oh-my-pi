---------SELECAO DE USER COM CONTRATO ATIVO, INQUILINO/MORADOR
WITH pos_list as (
  SELECT DISTINCT
    cast(fcp.sk_user as integer) sk_user,
    fcp.contract_role
  FROM
    dw_public.dim_contract dc
      LEFT JOIN
          dw_quintoandar.fact_contract_people fcp 
            ON dc.sk_contract = fcp.sk_contract
  WHERE
	  dc.status = 'Ativo'
    AND contract_role IN ('tenant', 'dweller')
    and sk_user <> -1
),
--SELECIONA OS USERS QUE ENTRARAM EM CONTATO NO NÚMERO PRINCIPAL 
users_contact as (
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
fix_count_strategy as (
  SELECT
    CAST(COALESCE(
          GET_JSON_OBJECT(memory, '$.legacy.user_data.user.id'),
          GET_JSON_OBJECT(memory, '$.basic.user.id')
      ) AS integer) AS id_user,
    COUNT(DISTINCT CAST(GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.whatsapp_strategy') AS string)) total_strategy
  FROM 
    datalake_greenseer_clean.session ss
  WHERE
    GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.has_access') is not  null
    AND DATE(ts_started) >= DATE('2023-01-19')
    AND DATE(ts_started) <= DATE(current_date)
  GROUP BY 1
),
fix_count_strategy_2 AS (
  SELECT 
    CAST(COALESCE(
            GET_JSON_OBJECT(memory, '$.legacy.user_data.user.id'),
            GET_JSON_OBJECT(memory, '$.basic.user.id')
        ) AS integer) AS id_user,
    COUNT(DISTINCT CAST(GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.whatsapp_strategy') AS string) is not null) total_strategy_2
  from 
    datalake_greenseer_clean.session ss
  where 
    GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.has_access') is not  null
    and date(ts_started) >= date('2023-04-01')
    and date(ts_started) <= date('2023-04-10')
  group by 1
),
--CONCATENA AS TABELAS E ATRIBUI UMA ORDEM PARA A CRIAÇÃO DE SESSÕES, FILTRA POR id_user AQUELES QUE SÃO IQ_PÓS E TRAZ SE HOUVE RETENÇÃO
base_origin as (
 SELECT DISTINCT 
    uc.id_session,
    uc.id_user,
    uc.ts_started,
    ROW_NUMBER() OVER(PARTITION BY uc.id_user ORDER BY uc.ts_started ASC) as session_ordem,
    uc.has_chat5a_access, 
    uc.migration_strategy,
    fcs.total_strategy,
    fcs2.total_strategy_2,
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
    LEFT JOIN 
      fix_count_strategy_2 fcs2 
        ON fcs2.id_user = uc.id_user     
),
--CSAT/DSAT BOT/ATENDIMENTO HUMANO
csat_dsat_bot as (
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
    SELECT distinct 
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
      RANK() OVER (PARTITION BY s.id ORDER BY s.ts_updated DESC) AS r,
      id_pipeline
    FROM 
      datalake_greenseer_clean.session AS gs
      LEFT JOIN 
        datalake_sauron_clean.session AS s 
          ON gs.id_session = s.id
    WHERE 
      id_pipeline IN ('in_app_main')
), 
classes as (
  select
    *,
    case 
      when cast(need_more_help_after_reception as string) = 'true' then 'precisa de ajuda'
      when cast(need_more_help_after_reception as string) = 'false' then 'não precisa de ajuda'
      when cast(need_more_help_after_reception as string) is null then 'não respondeu'
    end as resposta_pergunta_encerramento,
    case
        when (with_context > no_context and with_context > greeting and with_context > no_answer_needed) then
            (case when (with_context >= 0.5) then 'context' else 'sem_contexto' end)
        when (no_context > with_context and no_context > greeting and no_context > no_answer_needed) then 'sem_contexto'
        when (greeting > no_context and greeting > with_context and greeting > no_answer_needed) then 'saudacao'
        when (no_answer_needed > no_context and no_answer_needed > with_context and no_answer_needed > greeting) then 'sem_resposta'
        else 'erro'
    end as class
  from 
    base_status
), 
base_labels as (
  select  distinct
    gs.id_session,
    ts_started,
    case when class = 'sem_resposta' and resposta_pergunta_encerramento in ('não precisa de ajuda', 'não respondeu') then 'Retenção por cordialidade'
         when is_retention = true then 'Respondido sem transbordo'
         when selected_taxonomy is null and main_number = true and transferred = true and resposta_pergunta_encerramento in ('não respondeu') then 'Transbordo sem resposta'
         when selected_taxonomy is not null and main_number = true and transferred = true then 'Transbordo após resposta'
         when main_number = true and selected_taxonomy is null and transferred = false then 'Abandono'
         else 'Indefinido'
    end as tag
  from classes as c
  left join datalake_greenseer.greenseer_session as gs 
      on c.id_session = gs.id_session
  where 
       source = 'internal_chat'
       and status = 'expired'
       and (main_number or transferred) and r = 1
),
--TAG CHATBOT ADICIONADA
tag_chat as (
  select 
    cdb.*, 
    bl.tag
  from 
    csat_dsat_bot cdb
    left join
      base_labels bl on bl.id_session = cdb.id_session
),
--ADICIONANDO EVENTO TER APP
events_platform as (
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
events_platform_clean as (
   select 
     cast(trim('.' from id_user) as integer) id_user_inst,
     ts_event,
     platform
  from events_platform
),
tem_app as (
  select 
    id_user_inst,
    COUNT(distinct platform) total_plataformas
  from 
    events_platform_clean
  where 
    platform is not null
    and length(platform) > 2
group by 1
),
app_instalado as (
  select
    tc.*, 
    case
      when total_plataformas >= 1 then 'tem_app'
      when total_plataformas is null then 'sem_app'
      else null end as app_instalado
  from tag_chat tc
  left join tem_app ta on ta.id_user_inst = tc.id_user
),
--VALIDADOR DE ESTRATEGIAS, EM QUANTAS ESTRATEGIAS AS PESSOAS ESTAO
quais_estrategias as (
  select 
    id_user,
    count(distinct case when migration_strategy = 'last_open' and date(ts_started) < date('2023-04-01') then id_user end) last_open_1,
    count(distinct case when migration_strategy = 'close' and date(ts_started) < date('2023-04-01') then id_user end) close_1,
    count(distinct case when migration_strategy = 'suggest' and date(ts_started) < date('2023-04-01') then id_user end) suggest_1,
    count(distinct case when migration_strategy = 'open' and date(ts_started) < date('2023-04-01') then id_user end) open_1,
    count(distinct case when migration_strategy is not null and date(ts_started) < date('2023-04-01') then migration_strategy end) total_estrategias_1,
    count(distinct case when migration_strategy = 'last_open' and date(ts_started) >= date('2023-04-01') then id_user end) last_open_2,
    count(distinct case when migration_strategy = 'close' and date(ts_started) >= date('2023-04-01') then id_user end) close_2,
    count(distinct case when migration_strategy = 'suggest' and date(ts_started) >= date('2023-04-01') then id_user end) suggest_2,
    count(distinct case when migration_strategy = 'open' and date(ts_started) >= date('2023-04-01') then id_user end) open_2,
    count(distinct case when migration_strategy is not null and date(ts_started) >= date('2023-04-01') then migration_strategy end) total_estrategias_2
  from 
    app_instalado
  where 
    has_chat5a_access is not null
  group by 1
),
quantificador_mais_estrategias as (
  select 
    id_user,
    case 
      when  
        last_open_1 = 1 and
        close_1 = 1 and 
        open_1 = 1 and 
        suggest_1 = 1 
      then 'last_open + close + open + suggest'
      when  
        last_open_1 = 1 and
        close_1 = 1 and 
        open_1 = 1 and 
        suggest_1 = 0 
      then 'last_open + close + open'		  
      when  
        last_open_1 = 1 and
        close_1 = 1 and 
        open_1 = 0 and 
        suggest_1 = 1 
      then 'last_open + close + suggest'
      when  last_open_1 = 1 and
            close_1 = 1 and 
            open_1 = 0 and 
            suggest_1 = 1 then 'last_open + open + suggest'      
      when  last_open_1 = 0 and
            close_1 = 1 and 
            open_1 = 1 and 
            suggest_1 = 1 then 'close + open + suggest'	  
      when last_open_1 = 1 and 
            close_1 = 1 and
            open_1 = 0 and 
            suggest_1 = 0 then 'last_open + close'
      when last_open_1 = 1 and 
            close_1 = 0 and
            open_1 = 1 and 
            suggest_1 = 0 then 'last_open + open'
      when last_open_1 = 0 and 
            close_1 = 1 and
            open_1 = 1 and 
            suggest_1 = 0 then 'close + open'
      when last_open_1 = 0 and 
            close_1 = 0 and
            open_1 = 1 and 
            suggest_1 = 1 then 'suggest + open'
      when  last_open_1 = 1 and 
            close_1 = 0 and
            open_1 = 0 and 
            suggest_1 = 1 then 'last_open + suggest'  
      when  last_open_1 = 0 and 
            close_1 = 1 and
            open_1 = 0 and 
            suggest_1 = 1 then 'suggest + close'
      when  last_open_1 = 1 and 
            close_1 = 0 and
            open_1 = 0 and 
            suggest_1 = 0 then 'last_open'
      when  last_open_1 = 0 and 
            close_1 = 1 and
            open_1 = 0 and 
            suggest_1 = 0 then 'close'
      when  last_open_1 = 0 and 
            close_1 = 0 and
            open_1 = 1 and 
            suggest_1 = 0 then 'open'
      when  last_open_1 = 0 and 
            close_1 = 0 and
            open_1 = 0 and 
            suggest_1 = 1 then 'suggest'   
      else null     
    end as marcador_mais_estrategia,
    case
      when last_open_2 = 0 and 
            close_2 = 0 and
            open_2= 1 and 
            suggest_2 = 0 then 'open'
      when  last_open_2 = 0 and 
            close_2 = 0 and
            open_2 = 0 and 
            suggest_2 = 1 then 'suggest'   
      when last_open_2 = 0 and 
            close_2 = 0 and
            open_2 = 1 and 
            suggest_2 = 1 then 'suggest + open'
      else null     
    end as marcador_mais_estrategia_2     
  from quais_estrategias
),
com_contador_estrategias as (
  select 
    ai.*,
    qme.marcador_mais_estrategia,
    qme.marcador_mais_estrategia_2
  from 
    app_instalado ai
    left join 
      quantificador_mais_estrategias qme 
        on qme.id_user = ai.id_user
),
--ADICIONANDO A CONVERSAO E CRIANDO O MIGRATION_STRATEGY_AJUSTADO
--Devido a possibilidade de um mesmo id_user estar atrelado a duas estratégias (last_open e close), cria-se esse campo ajustado para uma contagem posterior
--de id_user por migration.
ajuste_estrategia as (
  select 
    *,
    case
    when has_chat5a_access is null and
      total_strategy is null and
      id_pipeline = 'in_app_main' and
      marcador_mais_estrategia is null and
      date(ts_started) >= date('2023-02-01') and
      migration_strategy is null 
      or 
      --regra de apoio a estrategia adotada em abril/23
      has_chat5a_access is null and
      total_strategy_2 is null and
      id_pipeline = 'in_app_main' and
      marcador_mais_estrategia_2 is null and
      date(ts_started) >= date('2023-04-01') and
      migration_strategy is null  	 
    then 'organic'
    when has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      marcador_mais_estrategia = 'open'
      or
      date(ts_started) < date('2023-02-01')
      or
      --regra de apoio a estrategia adotada em abril/23
      has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-04-01') and
      marcador_mais_estrategia_2 = 'open'
    then 'open'
    
    when has_chat5a_access is null and
      total_strategy is null and
      id_pipeline in ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy') and
      marcador_mais_estrategia is null and
      migration_strategy is null 
    then 'organic_whatsapp' 	 
    when has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      marcador_mais_estrategia = 'suggest' 
      or
      has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      marcador_mais_estrategia = 'suggest + open'
      --regra de apoio a estrategia adotada em abril/23
      or
      has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-04-01') and
      marcador_mais_estrategia_2 = 'suggest' 
      or
      has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-04-01') and
      marcador_mais_estrategia_2 = 'suggest + open'
    then 'suggest'	 
    
    when has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      date(ts_started) < date('2023-04-01') and
      marcador_mais_estrategia = 'close'
      or	 	 
        has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      date(ts_started) < date('2023-04-01') and
      marcador_mais_estrategia = 'close + open'
      or		 
        has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      date(ts_started) < date('2023-04-01') and
      marcador_mais_estrategia = 'last_open + close + open'
      or 
        has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      date(ts_started) < date('2023-04-01') and
      marcador_mais_estrategia = 'last_open + close'
      or 
        has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      date(ts_started) < date('2023-04-01') and
      marcador_mais_estrategia = 'last_open + close + open + suggest'
    then 'close' 
    when has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      date(ts_started) < date('2023-04-01') and
      marcador_mais_estrategia = 'last_open'
      or	 	 
        has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      date(ts_started) < date('2023-04-01') and
      marcador_mais_estrategia = 'last_open + open'
      or	 	 
        has_chat5a_access is null and
      migration_strategy is null and
      total_strategy is not null and
      id_pipeline = 'in_app_main' and
      date(ts_started) >= date('2023-02-01') and
      date(ts_started) < date('2023-04-01') and
      marcador_mais_estrategia = 'last_open + suggest'
    then 'last_open'
      
    when has_chat5a_access is not null  
        then
          case 
                  when date(ts_started) < date('2023-02-01') then 'open'
                  else
                  case 
                          when migration_strategy = 'suggest' and 
                              marcador_mais_estrategia = 'suggest' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'suggest' and 
                              marcador_mais_estrategia = 'suggest + open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'open' and
                              marcador_mais_estrategia = 'suggest + open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy is null and
                              marcador_mais_estrategia = 'suggest' and
                              total_strategy is not null and
                              date(ts_started) < date('2023-04-01')
                              or
                              --regra de apoio a estrategia adotada em abril/23
                              migration_strategy = 'suggest' and 
                              marcador_mais_estrategia_2 = 'suggest' and
                              date(ts_started) >= date('2023-04-01')
                              or
                              migration_strategy = 'suggest' and 
                              marcador_mais_estrategia_2 = 'suggest + open' and
                              date(ts_started) >= date('2023-04-01')
                              or
                              migration_strategy = 'open' and
                              marcador_mais_estrategia_2 = 'suggest + open' and
                              date(ts_started) >= date('2023-04-01')
                              or
                              migration_strategy is null and
                              marcador_mais_estrategia_2 = 'suggest' and
                              date(ts_started) >= date('2023-04-01') and
                              total_strategy is not null 
                              
                          then 'suggest'	
                          
                          when migration_strategy = 'open' and 
                              marcador_mais_estrategia = 'open'  and
                              date(ts_started) < date('2023-04-01')
                              
                              --regra de apoio a estrategia adotada em abril/23
                              or
                              migration_strategy = 'open' and 
                              marcador_mais_estrategia_2 = 'open' and
                              date(ts_started) >= date('2023-04-01')
                          then 'open'
                          
                          when migration_strategy = 'close' and 
                              marcador_mais_estrategia = 'close' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'close' and 
                              marcador_mais_estrategia = 'close + open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'open' and
                              marcador_mais_estrategia = 'close + open' and
                              date(ts_started) < date('2023-04-01')
                              or 
                              migration_strategy = 'last_open' and
                              marcador_mais_estrategia = 'last_open + close + open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'close' and
                              marcador_mais_estrategia = 'last_open + close + open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'open' and
                              marcador_mais_estrategia = 'last_open + close + open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'last_open' and
                              marcador_mais_estrategia = 'last_open + close' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'close' and
                              marcador_mais_estrategia = 'last_open + close' and
                              date(ts_started) < date('2023-04-01')
                              or
                migration_strategy = 'close' and
                              marcador_mais_estrategia = 'last_open + close + open + suggest' and
                              date(ts_started) < date('2023-04-01')
                              or
                migration_strategy = 'last_open' and
                              marcador_mais_estrategia = 'last_open + close + open + suggest' and
                              date(ts_started) < date('2023-04-01')
                              or
                migration_strategy = 'open' and
                              marcador_mais_estrategia = 'last_open + close + open + suggest' and
                              date(ts_started) < date('2023-04-01')
                              or
                migration_strategy = 'suggest' and
                              marcador_mais_estrategia = 'last_open + close + open + suggest' and
                              date(ts_started) < date('2023-04-01')
                          then 'close' 
                          
                          when migration_strategy = 'last_open' and 
                              marcador_mais_estrategia = 'last_open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'last_open' and
                              marcador_mais_estrategia = 'last_open + open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'open' and
                              marcador_mais_estrategia = 'last_open + open' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'last_open' and
                              marcador_mais_estrategia = 'last_open + suggest' and
                              date(ts_started) < date('2023-04-01')
                              or
                              migration_strategy = 'suggest' and
                              marcador_mais_estrategia = 'last_open + suggest' and
                              date(ts_started) < date('2023-04-01')
                              
                          then 'last_open'
                          else null
                      end 
              end 
    end as migration_strategy_adjusted,
    case 
          when id_pipeline = 'in_app_main' then 'chat5a'
          when id_pipeline in ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy') then 'whats_principal'
        else null 
      end as canal,
      case 
          when date(ts_started) < date('2023-02-01') then 'pre_estrategia'
        else 'pos_estrategia' 
      end as time_estrategia
  from com_contador_estrategias
),
tabela_conversao as (
  select 
    *, 
    case 
      when migration_strategy_adjusted in ('suggest','open','last_open') and 
           has_chat5a_access = true and
           lead(id_pipeline) over (partition by id_user order by ts_started asc) = 'in_app_main' and 
           lead(session_ordem) over (partition by id_user order by ts_started asc) = session_ordem + 1 
      then 'sim'
      when migration_strategy_adjusted = 'close' and 
           has_chat5a_access = true and
           lead(id_pipeline) over (partition by id_user order by ts_started asc) = 'in_app_main' and
           lead(session_ordem) over (partition by id_user order by ts_started asc) = session_ordem + 1
      then 'sim'
      when has_chat5a_access is null and
           migration_strategy is null and
           migration_strategy_adjusted in ('organic') and
           --total_strategy is null and
           id_pipeline = 'in_app_main' then 'sim'
      else null end as houve_conversao
  from ajuste_estrategia
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
  tu.app_instalado as has_installed_app,
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
  tabela_conversao tu
LEFT JOIN
  datalake_customer_support.chat atc
    ON tu.id_ticket = atc.id_ticket
