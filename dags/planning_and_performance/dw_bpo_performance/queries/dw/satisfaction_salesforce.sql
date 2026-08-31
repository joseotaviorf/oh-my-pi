WITH 


deletados as  (SELECT 

id_record,
event_type

FROM datalake_salesforce_clean.events_case 
WHERE event_type IN ('DELETE')

),

mkt_cloud AS (
  SELECT
    case__c AS sk_case,
    parse_url(survey_url__c, 'QUERY', 'mkt_cloud_trigger__c_id') AS trigger_id,
    account__c,
    email__c,
    COALESCE(
      NULLIF(parse_url(survey_url__c, 'QUERY', 'mkt_cloud_trigger__c_id'), '-1'),
      NULLIF(account__c, '-1'),
      NULLIF(case__c, '-1')
    ) AS key_trigger
  FROM datalake_salesforce_clean.events_mkt_cloud_trigger
),

----- Regra incremental 
----- Retorna ID que teve atualização de resposta 
answers as ( 
SELECT 
      COALESCE(NULLIF(fa.sk_trigger, '-1'), NULLIF(fa.sk_account, '-1'), NULLIF(fa.sk_case, '-1')) AS key_csat 
FROM dw_satisfaction_rating.fact_answer AS fa
WHERE 
      fa.sk_case IS NOT NULL AND
      fa.ts_submitted BETWEEN DATE('{load_start_date}') - INTERVAL 3 DAYS AND DATE('{load_end_date}')  
)

,base_csat AS (
    SELECT DISTINCT  
        fa.sk_case, 
        fa.ts_submitted,
        fa.sk_answer,
        fa.satisfaction_score,
        da.respondent_comments, 
        fa.sk_account,
        fa.is_solved,
        member_csat.type__c,
        fa.sk_trigger,
        CONCAT(
            fa.sk_case,
            COALESCE(NULLIF(fa.sk_trigger, '-1'), NULLIF(fa.sk_account, '-1'), NULLIF(fa.sk_case, '-1'))
        ) AS key_join,
        CASE 
            WHEN member_csat.type__c = 'Tenant' THEN 'Inquilino' 
            WHEN member_csat.type__c IN ('Owner','Landlord') THEN 'Proprietário' 
            ELSE 'Sem Definição de Partes' 
        END AS client_type_csat,
                mc.email__c AS email_cliente
    FROM dw_satisfaction_rating.fact_answer AS fa
    LEFT JOIN dw_satisfaction_rating.dim_answer AS da 
        ON da.sk_answer = fa.sk_answer
    LEFT JOIN datalake_salesforce_clean.events_case_member AS member_csat 
        ON member_csat.account__c = fa.sk_account 
       AND fa.sk_case = member_csat.case__c
       AND member_csat.type__c IN ('Owner','Tenant','Landlord')
        LEFT JOIN mkt_cloud AS mc 
        ON COALESCE(
             NULLIF(fa.sk_trigger, '-1'), 
             NULLIF(fa.sk_account, '-1'), 
             NULLIF(fa.sk_case, '-1')
           ) = mc.key_trigger
    WHERE fa.sk_case IS NOT NULL
       AND        COALESCE(NULLIF(fa.sk_trigger, '-1'), NULLIF(fa.sk_account, '-1'), NULLIF(fa.sk_case, '-1')) IN (SELECT key_csat FROM answers )
),

CSAT AS (
    SELECT 
        key_join,
        ts_submitted,
        sk_answer,
        sk_case,
        sk_trigger,
        type__c,
        sk_account,
        client_type_csat,
        email_cliente,
        
        -- Busca o satisfaction_score preenchido mais recente no Spark SQL
        FIRST_VALUE(satisfaction_score) OVER (
            PARTITION BY key_join 
            ORDER BY CASE WHEN satisfaction_score IS NOT NULL THEN 1 ELSE 2 END, ts_submitted ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS satisfaction_score,

        -- Busca o comentário do satisfaction_score preenchido mais recente
        FIRST_VALUE(respondent_comments) OVER (
            PARTITION BY key_join 
            ORDER BY CASE WHEN satisfaction_score IS NOT NULL THEN 1 ELSE 2 END, ts_submitted ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS respondent_comments,

        -- Busca o status is_solved preenchido mais recente
        FIRST_VALUE(is_solved) OVER (
            PARTITION BY key_join 
            ORDER BY CASE WHEN is_solved IS NOT NULL THEN 1 ELSE 2 END, ts_submitted ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS is_solved,

        -- Marca a linha mais recente da chave
        ROW_NUMBER() OVER (
            PARTITION BY key_join 
            ORDER BY ts_submitted ASC
        ) AS rn
    FROM base_csat
),
fact_request as (
    SELECT 
        sk_case,
        record_type_name
    FROM dw_support_journey.fact_requests as fr

    WHERE is_current = true
),

events_case as (
    SELECT 
        id_record,
        omni_channel_queue__c,
        contract_id__c AS sk_contract,
        c.case_number,
        created_date,
        closed_date,
        c.status,
        c.id_owner,
        c.type,
        fr.record_type_name,
        id_parent,
        event_type,
        last_modified_date,
        repair_contestation_responsibility_approved__c,
        TRY_CAST(fr_case_reopen_count__c AS INTEGER) AS reopen_count,
        ROW_NUMBER() OVER (PARTITION BY c.id_record ORDER BY c.last_modified_date DESC) as rn_case
    FROM datalake_salesforce_clean.events_case as c
    LEFT JOIN fact_request as fr on fr.sk_case = c.id_record 
    WHERE id_record IN (SELECT DISTINCT sk_case FROM csat)
), 

events_user as (
SELECT 
id_record,
email,
ROW_NUMBER() OVER (PARTITION BY id_record ORDER BY committed_at DESC) as rn_user
FROM datalake_salesforce_clean.events_user
),

status_historico AS (
    SELECT 
        CAST(case_number AS INT) AS case_number, 
        status,
        id_owner,
        -- No Spark, a subtração de horas é feita via INTERVAL
        CAST(last_modified_date AS TIMESTAMP) - INTERVAL 3 HOURS AS ts_event,
        ROW_NUMBER() OVER (PARTITION BY CAST(case_number AS INT) ORDER BY CAST(last_modified_date AS TIMESTAMP) DESC) AS rn,
        -- Pega o próximo status que o caso assumiu cronologicamente
        LEAD(status) OVER (
            PARTITION BY case_number 
            ORDER BY CAST(last_modified_date AS TIMESTAMP) ASC
        ) AS proximo_status
    FROM events_case
),

solved_date AS (
    SELECT 
        case_number,
        status,
        ts_event,
        eu.email,
        ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY ts_event ASC) AS rn
    FROM status_historico
    LEFT JOIN events_user as eu on eu.id_record = status_historico.id_owner and rn_user = 1  
    WHERE status = 'Solved'
),

solved_final AS (
SELECT DISTINCT
    c.case_number,
    CASE WHEN h.proximo_status IS NULL OR h.proximo_status IN ('Closed','Solved') THEN s.ts_event END as ts_solved,
    c.closed_date,
    CASE WHEN h.proximo_status IS NULL OR h.proximo_status IN ('Closed','Solved') THEN s.email END as agent_solved,
    CAST(c.created_date AS TIMESTAMP) - INTERVAL 3 HOURS as ts_created,
    h.proximo_status,
  ROW_NUMBER() OVER (PARTITION BY c.case_number ORDER BY MAX(c.last_modified_date) DESC) rn

FROM events_case as c
LEFT JOIN solved_date as s on s.case_number = CAST(c.case_number as INT) and s.rn = 1
LEFT JOIN status_historico as h on h.case_number = CAST(c.case_number as INT) and h.rn = 1
GROUP BY 1,2,3,4,5,6
),

first_open as (
    SELECT 
        cast(case_number as int) as case_number, 
        MIN(CAST(last_modified_date AS TIMESTAMP)) AS dt_first_open
    FROM events_case AS E
    WHERE status not in ('SelfService','Solved','Closed')
    GROUP BY cast(case_number as int) 
),

pedido_ajuda as (
    SELECT 
        case_id__c as id_case,
        follow_up_date__c as dt_pedido_ajuda,
        follow_up_help_action__c as motivo_pedido_ajuda,
        ROW_NUMBER() OVER (PARTITION BY case_id__c ORDER BY pa.ts_load ASC) rn
    FROM datalake_salesforce_clean.events_case_repair_follow_up as pa 
    WHERE follow_up_help_action__c IS NOT NULL 
),

contestacao_aprovada AS (
    SELECT 
        id_record, 
        id_parent,
        repair_contestation_responsibility_approved__c
    FROM events_case
    WHERE repair_contestation_responsibility_approved__c IS NOT NULL
    AND rn_case = 1 
),

repair_infiltracao AS (
    SELECT 
        c.id_parent AS id_case_pai,
        MAX(
            CASE 
                WHEN LOWER(it.repair_request_item_sub_category__c) LIKE '%infil%'
                THEN TRUE
                ELSE FALSE
            END
        ) AS flag_infiltracao
    FROM datalake_salesforce_clean.events_case_repair_item it
    INNER JOIN events_case c ON c.id_record = it.case__c AND rn_case = 1
    WHERE c.id_parent IS NOT NULL
    GROUP BY c.id_parent
),

csat_final as (
    SELECT DISTINCT
        csat.sk_answer as sk_answer_csat,
        csat.ts_submitted as first_csat_ts_response, 
        csat.satisfaction_score as first_csat_score,
        csat.respondent_comments as first_csat_comment,
        MAX(csat.client_type_csat) AS client_type_csat,
        csat.is_solved,
        c.id_record as id_case,
        omni_channel_queue__c as fila_omni_channel, 
        CASE WHEN record_type_name = 'Solicitação de Reparos' THEN record_type_name ELSE COALESCE(omni_channel_queue__c, record_type_name) END as last_department,
        cast(c.case_number AS INT) as case_number,
        record_type_name,
        CAST(c.created_date AS TIMESTAMP) - INTERVAL 3 HOURS as ts_created, 
        sd.ts_solved as ts_solved,
        CAST(c.closed_date AS TIMESTAMP) - INTERVAL 3 HOURS as ts_closed,
        c.status,
        f.dt_first_open,
        c.type as criticidade,
        COALESCE(sf.email_analista, sd.agent_solved,u.email) as last_agent_email,
        CASE WHEN COALESCE(sf.email_analista, sd.agent_solved,u.email) LIKE '%webhelp%' THEN 'webhelp'
             WHEN COALESCE(sf.email_analista, sd.agent_solved,u.email) LIKE '%concentrix%' THEN 'webhelp'
             WHEN COALESCE(sf.email_analista, sd.agent_solved,u.email) LIKE '%atento%' THEN 'atento'
             WHEN COALESCE(sf.email_analista, sd.agent_solved,u.email) LIKE '%aec%' THEN 'aec'
             WHEN COALESCE(sf.email_analista, sd.agent_solved,u.email) LIKE '%quintoandar%' THEN 'quintoandar'
             END as last_agent_organization,
        dc.ts_termination_requested,
        dc.dt_start,
        CASE
            WHEN dc.dt_start IS NULL THEN NULL
            WHEN datediff(CAST(c.created_date AS TIMESTAMP), dc.dt_start) <= 40 THEN 'ONB'
            ELSE 'ONG'
        END AS contract_journey,
        pa.dt_pedido_ajuda,
        pa.motivo_pedido_ajuda,
        CASE WHEN ca.repair_contestation_responsibility_approved__c = 'true' then TRUE END AS contestacao_aprovada,
        c.reopen_count,
        COALESCE(ri.flag_infiltracao, FALSE) AS is_infiltracao,
        CASE
            WHEN f.dt_first_open IS NOT NULL
            THEN date_add(f.dt_first_open, 1)
        END AS dt_max_fr,
        CASE
            WHEN c.type = 'Common'
                THEN date_add(CAST(c.created_date AS TIMESTAMP), 21)
            WHEN c.type = 'Urgent'
                THEN date_add(CAST(c.created_date AS TIMESTAMP), 19)
            WHEN c.type = 'Emergency'
                THEN date_add(CAST(c.created_date AS TIMESTAMP), 3)
        END AS dt_max_end,
        email_cliente

    FROM csat as csat 
    LEFT JOIN events_case as c on c.id_record = csat.sk_case and rn_case = 1 
    LEFT JOIN solved_final as sd on CAST(sd.case_number AS int) = CAST(c.case_number AS int) and sd.rn = 1
    LEFT JOIN first_open AS f ON CAST(f.case_number AS INT) = CAST(c.case_number AS INT)
    LEFT JOIN events_user as u on u.id_record = c.id_owner and u.rn_user = 1
    LEFT JOIN dw_rent.dim_contract dc ON TRY_CAST(c.sk_contract AS BIGINT) = dc.sk_contract
    LEFT JOIN pedido_ajuda as pa on pa.id_case = c.id_record and pa.rn = 1
    LEFT JOIN contestacao_aprovada as ca on ca.id_parent = c.id_record
    LEFT JOIN sandbox.analistas_reparos_sf as sf on cast(sf.case_number as int) = cast(c.case_number as int)
    LEFT JOIN repair_infiltracao ri ON ri.id_case_pai = c.id_record
  
    WHERE  c.id_record NOT IN (SELECT id_record FROM deletados)
AND (CSAT.rn = 1)

    GROUP BY 1,2,3,4,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30
),

csat_final_ajustado AS (
    SELECT
        cf.*,
        CASE
            WHEN ddend.is_brz_holiday = 'Holiday'
              -- Spark SQL: dayofweek retorna 7 para Sábado. No Spark, Domingo é 1.
              OR dayofweek(cf.dt_max_end) = 7
            THEN date_add(cf.dt_max_end, 1)
            ELSE cf.dt_max_end
        END AS dt_max_end_ajustado
    FROM csat_final cf
    LEFT JOIN dw_public.dim_date ddend
        ON ddend.date = CAST(cf.dt_max_end AS DATE)
)
SELECT 
    sk_answer_csat,
    first_csat_ts_response,
    first_csat_score,
    first_csat_comment,
    client_type_csat,
    is_solved,
    id_case,
    fila_omni_channel,
    last_department,
    case_number,
    record_type_name,
    ts_created,
    ts_solved,
    ts_closed,
    status,
    dt_first_open,
    criticidade,
    last_agent_email,
    last_agent_organization,
    ts_termination_requested,
    dt_start,
    contract_journey,
    dt_pedido_ajuda,
    motivo_pedido_ajuda,
    contestacao_aprovada,
    reopen_count,
    is_infiltracao,
    dt_max_fr,
    dt_max_end,
    dt_max_end_ajustado,
    email_cliente,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM csat_final_ajustado
