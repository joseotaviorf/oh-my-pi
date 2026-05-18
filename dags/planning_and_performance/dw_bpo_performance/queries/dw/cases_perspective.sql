WITH weekends_and_holidays AS (
    SELECT
        ad.date AS dt_non_working
    FROM
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.weekend = 'Weekend' 
    UNION
    SELECT
        sch.dt_holiday AS dt_non_working
    FROM
        datalake_gsheets_clean.service_city_holidays AS sch
    WHERE
        sch.category = 'Nacional'
),

csat AS (
    SELECT 
        sk_case, 
        fa.ts_submitted,
        fa.sk_answer,
        satisfaction_score,
        respondent_comments, 
        fa.is_solved
    FROM dw_satisfaction_rating.fact_answer as fa
    LEFT JOIN dw_satisfaction_rating.dim_answer as da on da.sk_answer = fa.sk_answer

    WHERE satisfaction_score IS NOT NULL
        QUALIFY ROW_NUMBER() OVER (PARTITION BY sk_case ORDER BY fa.ts_submitted ASC) = 1  
),

spoc AS (
  SELECT 
    ft.sk_termination,
    ft.sk_contract,
    ft.ts_termination_request,
    ft.ts_termination_finished,
    ft.ts_termination_canceled,
    ft.is_spoc_contract,
    ft.spoc_wave,
    ft.is_spoc_control_group,
    dit.team as spoc_team,
    dit.has_mediation,
    dit.has_ac_repairs,
    dit.dt_inspection,
    CASE 
      WHEN ts_termination_request < DATE('2025-05-22') AND is_spoc_contract = TRUE AND (is_spoc_control_group = FALSE OR is_spoc_control_group IS NULL) THEN 'before_wave_6_lab_test'
      WHEN ts_termination_request < DATE('2025-05-22') AND is_spoc_contract = TRUE AND is_spoc_control_group = TRUE THEN 'before_wave_6_lab_control'
      WHEN ts_termination_request >= DATE('2025-05-22') AND is_spoc_contract = TRUE AND (is_spoc_control_group = FALSE OR is_spoc_control_group IS NULL) AND (dit.team IN ('ROLLOUT','BAU_LONG_LDT','BAU_SHORT_LDT') OR dit.team IS NULL) THEN 'rollout'
      WHEN ts_termination_request >= DATE('2025-05-22') AND is_spoc_contract = TRUE AND (is_spoc_control_group = FALSE OR is_spoc_control_group IS NULL) AND dit.team = 'LAB' THEN 'lab_test'
      WHEN ts_termination_request >= DATE('2025-05-22') AND is_spoc_contract = TRUE AND is_spoc_control_group = TRUE THEN 'lab_control'
    ELSE NULL
    END as spoc_class
  FROM dw_offboarding.fact_terminations as ft
  LEFT JOIN dw_offboarding.dim_termination dit ON ft.sk_termination = dit.sk_termination
  WHERE ft.ts_termination_canceled IS NULL AND ft.ts_termination_request >= DATE('2025-01-01')
),

record_types AS (
    SELECT 
        id_record_type,
        ts_last_modified,
        record_type_name,
        developer_name
    FROM datalake_salesforce_clean.record_types 
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_record_type ORDER BY ts_last_modified DESC) = 1  
),

first_reply_sf AS (
    SELECT
        c.id_case,
        c.case_number,
        CAST(c.ts_created AS TIMESTAMP) - INTERVAL 7 HOURS AS ts_created,
        MIN(e.ts_message - INTERVAL 7 HOURS) AS ts_first_reply,
        COUNT(DISTINCT ts_message) as replies,
        -- Cálculo de diferença em minutos no Spark
        (CAST(MIN(e.ts_message - INTERVAL 7 HOURS) AS LONG) - CAST((CAST(c.ts_created AS TIMESTAMP) - INTERVAL 7 HOURS) AS LONG)) / 60 AS minutes_first_reply_time_business
    FROM datalake_salesforce_clean.cases c
    INNER JOIN datalake_salesforce_clean.email_message e ON c.id_case = e.id_parent
    WHERE e.ts_message IS NOT NULL AND e.is_incoming = FALSE
    GROUP BY c.id_case, c.case_number, c.ts_created
),

first_resolution AS (
  SELECT 
    COALESCE(tp.last_agent_email, u.email) as last_agent_email, 
    MIN(COALESCE(tp.ts_solved, c.ts_closed)) as first_resolution 
  FROM dw_bpo_performance.tickets_perspective AS tp
  LEFT JOIN datalake_salesforce_clean.users as u on u.email = tp.last_agent_email
  LEFT JOIN datalake_salesforce_clean.cases as c on c.id_owner = u.id_user_salesforce
  GROUP BY 1 
),

tickets_perspective AS (
    SELECT 
        tp.sk_ticket as case_number,
        CAST(tp.sk_contract as STRING) as sk_contract,
        tp.sk_user,
        tp.ts_started,
        tp.ts_solved,
        tp.ts_closed,
        tp.channel,
        tp.status,
        CASE WHEN last_department = '[AeC] CX Pagamentos [FRONT] [POS]' THEN 'CX Pagamentos [FRONT] [POS]'  
             WHEN last_department = '[AeC] CX Rescisão [FRONT] [POS]' THEN 'CX Rescisão [FRONT] [POS]' 
             WHEN last_department = '[AeC] CX Mudança [FRONT] [POS]' THEN 'CX Mudança [FRONT] [POS]'
             WHEN last_department = '[AeC] CX Reparos [FRONT] [POS]' THEN 'CX Reparos [FRONT] [POS]'
             WHEN last_department = '[AeC] CX Propostas [FRONT] [PRE]' THEN 'CX Propostas [FRONT] [PRE]'
             WHEN last_department = '[AeC] CX Visitas [FRONT] [PRE]' THEN 'CX Visitas [FRONT] [PRE]'
             WHEN last_department = '[AeC] CX Parceiros [FRONT] [PRE]' THEN 'CX Parceiros [FRONT] [PRE]'
             ELSE last_department END AS last_department, 
        last_team,
        last_area,
        front_or_back,
        theme,
        theme_detail,
        theme_recontact_flag_d4,
        theme_recontact_flag_d0,
        is_ticket_solved_within_sla,
        CASE WHEN canal_de_entrada = 'Api / PWA' AND group_name_ro IS NOT NULL THEN 1 ELSE 0 END as is_auto_reparo,
        minutes_first_reply_time_business,
        tp.subject,
        first_csat_ts_response,
        first_csat_score,
        first_csat_comment,
        resolution_survey,
        tp.last_agent_email,
        last_agent_organization,
        CASE WHEN spoc.is_spoc_contract = TRUE AND spoc.spoc_class IN ('before_wave_6_lab_test', 'lab_test', 'rollout') THEN TRUE ELSE FALSE END is_spoc_test,
        is_pp_multi,
        first_resolution,
        tp.reopens,
        off_area,
        tp.tags,
        tp.replies,
        tp.ticket_type,
        tp.canal_de_entrada,
        tp.criticidade_ro,
        tp.group_name_ro,
        CASE WHEN (CASE WHEN ddend.is_brz_holiday = 'Holiday' OR dayofweek(deadline_ticket_reparos) = 1 THEN date_add(deadline_ticket_reparos, 1) ELSE deadline_ticket_reparos END) >= TS_SOLVED THEN 1 ELSE 0 END as flag_sla_reparos,
        CASE WHEN COALESCE(date(spoc.ts_termination_finished), current_date()) >= ww_backlog.dt_end_9 THEN 0 ELSE 1 END as flag_sla_med,
        IF(dt.group_name = 'Rescisão por Inadimplência [OFF][POS][BACK]' 
            AND tp.tipo_de_cliente LIKE '%proprietário%' AND tp.tipo_de_demanda IN ('demanda_de_processos') 
            AND tp.tipo_de_processo IN ('despejo/fraude') AND dt.subject LIKE '%Rescisão do contrato%', 'despejo', NULL ) as tkt_despejo,
            tp.tipo_de_cliente,
        'Zendesk' as Platform
    FROM dw_bpo_performance.tickets_perspective as tp
    LEFT JOIN spoc ON tp.sk_contract = spoc.sk_contract
    LEFT JOIN first_resolution AS fr on fr.last_agent_email = tp.last_agent_email
    LEFT JOIN dw_public.dim_date as ddend ON ddend.date = deadline_ticket_reparos
    LEFT JOIN datalake_date.workday_window AS ww_backlog ON date(tp.ts_started) = ww_backlog.dt_ref AND ww_backlog.id_city = 39
    LEFT JOIN dw_customer_support.dim_ticket as dt on dt.sk_ticket = tp.sk_ticket 
    QUALIFY ROW_NUMBER() OVER (PARTITION BY tp.sk_ticket ORDER BY tp.ts_load DESC) = 1 
),

solved_date AS (
    SELECT 
        CAST(case_number as INT) as case_number, 
        status, 
        to_timestamp(last_modified_date) - INTERVAL 7 HOURS as ts_event
    FROM datalake_salesforce_clean.events_Case AS E
    WHERE status = 'Solved'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY to_timestamp(last_modified_date) ASC) = 1 
),

case_non_working_days AS (
    SELECT 
        c.id_case,
        COUNT(wh.dt_non_working) as total_non_working
    FROM datalake_salesforce_clean.cases c
    LEFT JOIN solved_date sd ON sd.case_number = c.case_number 
    LEFT JOIN weekends_and_holidays wh ON wh.dt_non_working BETWEEN CAST(c.ts_created AS DATE) AND COALESCE(CAST(COALESCE(c.ts_closed, sd.ts_event) AS DATE), CURRENT_DATE())
    GROUP BY c.id_case
),

 events as (

SELECT 

CAST(case_number as INT) AS case_number,
reason as case_reason,
omni_channel_queue__c as fila_omni_channel,
fr_case_reopen_count__c as reopens,
inspection_external_id__c as id_inspection,
property_id__c as id_house,
is_eviction__c as is_eviction,
is_pp_multi__c as is_pp_multi,
is_kirk__c as is_kirk,
is_high_value__c as is_high_value,
client_type__c as client_type,
criticality__c as criticidade,
criticality_sla__c AS criticidade_sla,
sla_due_days__c as sla_target,
event_type  as event_type

FROM datalake_salesforce_clean.events_case
QUALIFY ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY last_modified_date DESC) = 1 
),


cases_perspective AS (
    SELECT DISTINCT
        c.id_case,
        c.case_number,
        c.id_contract,
        du.sk_user,
        external_id__c,
        sla.ops as team,
        sla.Front_Or_Back,	
        sla.Pre_Pos,	
        sla.Area,
        sla.ops,
        c.case_status, 
        c.case_subject as subject,
        rt.record_type_name,	
        rt.developer_name as theme,
        case_type,
        c.ts_created,
        sd.ts_event as ts_solved,
        c.ts_closed,
        csat.sk_answer as sk_answer_csat,
        csat.ts_submitted as first_csat_ts_response, 
        csat.satisfaction_score as first_csat_score,
        csat.respondent_comments as first_csat_comment,
        csat.is_solved,
        c.ts_created + (INTERVAL 1 MINUTE * fr.minutes_first_reply_time_business) AS data_first_reply,
        fr.minutes_first_reply_time_business AS minutes_first_reply_time_business,
        fr.replies,
        datediff(c.ts_closed, c.ts_created) as ldt_ticket,
        COALESCE(cm.target_response_in_days,CAST(sla.sla_tgt as INT)) as sla_tgt,

CASE 
            WHEN ts_closed IS NULL THEN NULL 
            WHEN (datediff(CAST(COALESCE(c.ts_closed, sd.ts_event) AS DATE), CAST(c.ts_created AS DATE)) - COALESCE(cnw.total_non_working, 0)) <=  COALESCE(cm.target_response_in_days,CAST(sla.sla_tgt as INT)) THEN TRUE 
            ELSE FALSE 
        END as is_ticket_solved_within_sla,
        u.email as agent_email,
        CASE WHEN u.email LIKE '%webhelp%' THEN 'webhelp'
             WHEN u.email LIKE '%atento%' THEN 'atento'
             WHEN u.email LIKE '%aec%' THEN 'aec'
             WHEN u.email LIKE '%quintoandar%' THEN 'quintoandar'
             END as agent_organization,
        CASE WHEN rt.record_type_name RLIKE '\\[NÃO UTILIZAR\\]' THEN 'Sim' ELSE 'Não' END as flag_teste,
        spoc.is_spoc_contract,
        spoc.spoc_wave,
        spoc.is_spoc_control_group,
        spoc.spoc_team,
        spoc.spoc_class,
        CASE WHEN spoc.is_spoc_contract = TRUE AND spoc.spoc_class IN ('before_wave_6_lab_test', 'lab_test', 'rollout') THEN TRUE ELSE FALSE END as is_spoc_test,
        c.case_origin, 
        fr_res.first_resolution,
        CASE WHEN c.case_type LIKE '%Mediation%' THEN 'MED' END as off_area,
        CASE WHEN COALESCE(date(spoc.ts_termination_finished), current_date()) >= ww_backlog.dt_end_9 THEN 0 ELSE 1 END as flag_sla_med,
        c.supplied_email,
        e.case_reason,
        e.fila_omni_channel,
        e.reopens,
        e.id_inspection,
        e.id_house,
        e.is_eviction,
        e.is_pp_multi,
        e.is_kirk,
        e.is_high_value,
        e.client_type,
        e.criticidade,
        e.criticidade_sla,
        e.event_type,
        CASE WHEN c.omni_channel_queue = 'Squad 7 - Mediação' THEN 'despejo' ELSE NULL END as tkt_despejo,
        'email' as channel,
        'SalesForce' as Platform 

    FROM datalake_salesforce_clean.cases as c
    LEFT JOIN record_types as rt on rt.id_record_type = c.id_record_type
    LEFT JOIN csat as csat on csat.sk_case = c.id_Case 
    LEFT JOIN sandbox.sla_target_salesforce as sla on sla.theme_type = COALESCE(CONCAT(rt.developer_name, c.case_type), rt.developer_name)
    LEFT JOIN datalake_salesforce_clean.users as u on u.id_user_salesforce = c.id_owner
    LEFT JOIN datalake_salesforce_clean.account as a on a.id_account = c.id_account
    LEFT JOIN spoc ON CAST(c.id_contract AS STRING) = CAST(spoc.sk_contract AS STRING)
    LEFT JOIN first_reply_sf AS fr ON fr.id_case = c.id_case
    LEFT JOIN first_resolution AS fr_res on fr_res.last_agent_email = u.email
    LEFT JOIN datalake_date.workday_window AS ww_backlog ON date(C.ts_created) = ww_backlog.dt_ref AND ww_backlog.id_city = 39
    LEFT JOIN solved_date as sd on sd.case_number = c.case_number 
    LEFT JOIN datalake_salesforce_clean.events_case_member as cm on cm.case__c = c.id_Case AND type__c = 'Service requester'
    LEFT JOIN dw_public.dim_user as du on du.uuid_person = split(cm.external_id__c, '_')[2] 
    LEFT JOIN case_non_working_days cnw ON cnw.id_case = c.id_case 
    LEFT JOIN datalake_salesforce_clean.case_milestones  as cm on cm.id_case = c.id_case
    LEFT JOIN events AS e on e.case_number = c.case_number
    QUALIFY ROW_NUMBER() OVER (PARTITION BY c.case_number ORDER BY c.TS_LAST_MODIFIED DESC) = 1
)

SELECT
    case_number,
    ts_created as ts_started,
    COALESCE(ts_solved, ts_closed) as ts_solved, 
    ts_closed as ts_closed,
    id_contract as sk_contract,
    sk_user as sk_user,
    channel,
    case_status as status,
    fila_omni_channel as last_team,
    Area as last_area,
    front_or_back,
    COALESCE(fila_omni_channel, record_type_name) as last_department,
    first_csat_ts_response,
    first_csat_score,
    first_csat_comment,
    is_solved AS resolution_survey,
    minutes_first_reply_time_business,
    subject,
    theme,
    case_type as theme_detail,
    NULL AS theme_recontact_flag_d4,
    NULL AS theme_recontact_flag_d0,
    is_ticket_solved_within_sla,
    agent_email as last_agent_email,
    agent_organization as last_agent_organization,
    reopens AS reopens,
    is_spoc_test,
    is_pp_multi,
    off_area,
    NULL AS tags,
    replies,
    NULL AS ticket_type,
    client_type,
    case_origin AS canal_de_entrada,
    NULL AS is_auto_reparo,
    NULL AS group_name_ro,
    criticidade AS criticidade_ro,
    NULL AS flag_sla_reparos,
    flag_sla_med,
    tkt_despejo AS tkt_despejo,
    first_resolution as first_resolution_last_agent,
    id_inspection,
    id_house,
    is_eviction, 
    is_kirk,
    is_high_value,
    criticidade_sla,
    event_type,
    supplied_email,
    Platform,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM cases_perspective

UNION ALL 

SELECT 
    case_number,
    ts_started,
    ts_solved,
    ts_closed,
    sk_contract,
    CAST(sk_user AS STRING) AS sk_user,
    channel,
    status,
    last_team,
    last_area,
    front_or_back,
    last_department,
    first_csat_ts_response,
    first_csat_score,
    first_csat_comment,
    resolution_survey,
    minutes_first_reply_time_business,
    subject,
    theme,
    theme_detail,
    theme_recontact_flag_d4,
    theme_recontact_flag_d0,
    is_ticket_solved_within_sla,
    last_agent_email,
    last_agent_organization,
    reopens,
    is_spoc_test,
    is_pp_multi,
    off_area,
    tags,
    replies,
    ticket_type,
    tipo_de_cliente as client_type,
    canal_de_entrada,
    is_auto_reparo,
    group_name_ro,
    criticidade_ro,
    flag_sla_reparos,
    flag_sla_med,
    tkt_despejo,
    first_resolution as first_resolution_last_agent,
    NULL AS id_inspection,
    NULL AS id_house, 
    NULL AS is_eviction,
    NULL AS supplied_email,
    NULL AS is_kirk,
    NULL AS is_high_value,
    NULL AS criticidade_sla,
    NULL AS event_type,
    Platform,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM tickets_perspective
