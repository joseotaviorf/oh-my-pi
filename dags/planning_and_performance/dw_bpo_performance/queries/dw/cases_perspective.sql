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
        fa.is_solved,
        ROW_NUMBER() OVER (PARTITION BY sk_case ORDER BY fa.ts_submitted ASC) as rn
    FROM dw_satisfaction_rating.fact_answer as fa
    LEFT JOIN dw_satisfaction_rating.dim_answer as da on da.sk_answer = fa.sk_answer

    WHERE satisfaction_score IS NOT NULL
    AND sk_case is not null
),

dirty_cases_sf AS (
    SELECT DISTINCT
        CAST(case_number AS INT) AS case_number,
        sk_case
    FROM dw_support_journey.fact_requests as fr
    WHERE ts_last_modified BETWEEN DATE('{load_start_date}') - INTERVAL 3 DAYS AND DATE('{load_end_date}')

    UNION ALL

    --- Retorna casos que teve CSAT mas não teve atualização na Events
    SELECT DISTINCT
        CAST(c.case_number AS INT) AS case_number,
        c.id_record AS sk_case
    FROM csat AS csat
    LEFT JOIN datalake_salesforce_clean.events_case AS c ON c.id_record = csat.sk_case
    WHERE ts_submitted BETWEEN DATE('{load_start_date}') - INTERVAL 7 DAYS AND DATE('{load_end_date}')
),

dw_cases_dirty AS (
    SELECT *
    FROM dw_support_journey.fact_requests
    WHERE sk_case IN (SELECT sk_case FROM dirty_cases_sf)
    AND is_current = true
),

events_case_dirty AS (
    SELECT *,
    ROW_NUMBER() OVER (PARTITION BY id_record ORDER BY to_timestamp(last_modified_date) DESC) as rn
    FROM datalake_salesforce_clean.events_case
    WHERE id_record IN (SELECT sk_case FROM dirty_cases_sf)
),

first_open as (
    SELECT
        cast(case_number as int) as case_number,
        id_record as sk_case,
        MIN(CAST(last_modified_date AS TIMESTAMP) - INTERVAL 3 HOURS) AS dt_first_open
    FROM datalake_salesforce_clean.events_Case AS E
    WHERE id_record IN (SELECT sk_case FROM dirty_cases_sf)
    AND status not in ('SelfService','Solved','Closed')
    GROUP BY 1,2
),

deletados as  (
    SELECT
        id_record,
        event_type
    FROM datalake_salesforce_clean.events_case
    WHERE event_type IN ('DELETE')
),

status_historico AS (
    SELECT
        CAST(case_number AS INT) AS case_number,
        status,
        id_owner,
        CAST(last_modified_date AS TIMESTAMP) - INTERVAL 3 HOURS AS ts_event,
        ROW_NUMBER() OVER (PARTITION BY CAST(case_number AS INT) ORDER BY CAST(last_modified_date AS TIMESTAMP) DESC) AS rn,

        -- NOVA COLUNA: Mapeia o status da linha imediatamente anterior
        LAG(status) OVER (
            PARTITION BY case_number
            ORDER BY CAST(last_modified_date AS TIMESTAMP) ASC
        ) AS status_anterior,

        LEAD(status) OVER (
            PARTITION BY case_number
            ORDER BY CAST(last_modified_date AS TIMESTAMP) ASC
        ) AS proximo_status
    FROM events_case_dirty
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

first_reply_sf AS (
    SELECT
        fr.sk_case as id_case,
        CAST(fr.case_number AS INT) as case_number,
        CAST(fr.ts_created AS TIMESTAMP) - INTERVAL 3 HOURS AS ts_created,
        fo.dt_first_open,
        MIN(CAST(e.message_date AS TIMESTAMP) - INTERVAL 3 HOURS) AS ts_first_reply,
        COUNT(DISTINCT e.id_record) as replies
    FROM dw_support_journey.fact_requests as fr
    INNER JOIN datalake_salesforce_clean.events_email_message e ON fr.sk_case = e.id_parent
    LEFT JOIN first_open AS fo on fo.sk_case = fr.sk_case
    WHERE e.message_date IS NOT NULL AND e.incoming = FALSE
      AND fr.sk_case IN (SELECT sk_case FROM dirty_cases_sf)
    GROUP BY fr.sk_case, CAST(fr.case_number AS INT), CAST(fr.ts_created AS TIMESTAMP), fo.dt_first_open
),

days_expanded AS (
    SELECT
        *,
        explode(sequence(to_date(ts_created), to_date(ts_first_reply))) AS current_day
    FROM first_reply_sf
),

business_days_only AS (
    SELECT d.*
    FROM days_expanded d
    LEFT JOIN weekends_and_holidays w ON d.current_day = w.dt_non_working
    WHERE w.dt_non_working IS NULL
),

daily_minutes AS (
    SELECT
        *,
        CASE
            WHEN to_date(ts_created) = to_date(ts_first_reply) THEN
                (CAST(LEAST(ts_first_reply, to_timestamp(concat(current_day, ' 21:00:00'))) AS LONG) -
                 CAST(GREATEST(ts_created, to_timestamp(concat(current_day, ' 08:00:00'))) AS LONG)) / 60.0
            WHEN current_day = to_date(ts_created) THEN
                (CAST(to_timestamp(concat(current_day, ' 21:00:00')) AS LONG) -
                 CAST(GREATEST(ts_created, to_timestamp(concat(current_day, ' 08:00:00'))) AS LONG)) / 60.0
            WHEN current_day = to_date(ts_first_reply) THEN
                (CAST(LEAST(ts_first_reply, to_timestamp(concat(current_day, ' 21:00:00'))) AS LONG) -
                 CAST(to_timestamp(concat(current_day, ' 08:00:00')) AS LONG)) / 60.0
            ELSE 780.0
        END AS minutes_calc,
        CASE
            WHEN dt_first_open IS NULL THEN 0.0
            WHEN current_day < to_date(dt_first_open) THEN 0.0

            WHEN to_date(dt_first_open) = to_date(ts_first_reply) AND current_day = to_date(dt_first_open) THEN
                (CAST(LEAST(ts_first_reply, to_timestamp(concat(current_day, ' 21:00:00'))) AS LONG) -
                 CAST(GREATEST(dt_first_open, to_timestamp(concat(current_day, ' 08:00:00'))) AS LONG)) / 60.0
            WHEN current_day = to_date(dt_first_open) THEN
                (CAST(to_timestamp(concat(current_day, ' 21:00:00')) AS LONG) -
                 CAST(GREATEST(dt_first_open, to_timestamp(concat(current_day, ' 08:00:00'))) AS LONG)) / 60.0
            WHEN current_day = to_date(ts_first_reply) THEN
                (CAST(LEAST(ts_first_reply, to_timestamp(concat(current_day, ' 21:00:00'))) AS LONG) -
                 CAST(to_timestamp(concat(current_day, ' 08:00:00')) AS LONG)) / 60.0
            ELSE 780.0
        END AS minutes_calc_open

    FROM business_days_only
),

first_reply_final as (
    SELECT
        id_case,
        case_number,
        ts_created,
        dt_first_open,
        ts_first_reply,
        replies,
        SUM(GREATEST(0, minutes_calc)) AS minutes_first_reply_time_business,
        (CAST(ts_first_reply AS LONG) - CAST(ts_created AS LONG)) / 60.0 AS minutes_first_reply_time_calendar,
        SUM(GREATEST(0, minutes_calc_open)) AS minutes_first_reply_open_time_business,
        (CAST(ts_first_reply AS LONG) - CAST(dt_first_open AS LONG)) / 60.0 AS minutes_first_reply_open_time_calendar

    FROM daily_minutes
    GROUP BY
        id_case,
        case_number,
        ts_created,
        dt_first_open,
        ts_first_reply,
        replies
),


fr_agent_ticket AS (
    SELECT
        last_agent_email,
        MIN(CAST(ts_solved AS TIMESTAMP)) AS min_ts_solved,
        MAX(CASE WHEN ts_solved IS NULL THEN 1 ELSE 0 END) AS has_null_solved
    FROM dw_bpo_performance.tickets_perspective
    WHERE last_agent_email IS NOT NULL
    GROUP BY last_agent_email
),

fr_agent_case AS (
    SELECT
        da.email AS last_agent_email,
        MIN(CAST(fr.ts_closed AS TIMESTAMP)) AS min_case_closed
    FROM dw_support_journey.dim_analyst AS da
    INNER JOIN dw_support_journey.fact_requests AS fr ON fr.sk_owner = da.sk_analyst
    WHERE da.email IS NOT NULL
    AND da.is_current = true
    GROUP BY da.email
),

first_resolution AS (
    SELECT
        at.last_agent_email,
        LEAST(
            at.min_ts_solved,
            CASE WHEN at.has_null_solved = 1 THEN ac.min_case_closed END
        ) AS first_resolution
    FROM fr_agent_ticket AS at
    LEFT JOIN fr_agent_case AS ac ON ac.last_agent_email = at.last_agent_email
),

tp_dirty_ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY sk_ticket ORDER BY ts_load DESC) AS rn_dirty
    FROM dw_bpo_performance.tickets_perspective
    WHERE MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')  - INTERVAL 3 DAYS AND DATE('{load_end_date}')
),

tp_dirty AS (
    SELECT *
    FROM tp_dirty_ranked
    WHERE rn_dirty = 1
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
        tp.sla_target as sla_tgt,
        tp.tags,
        tp.replies,
        tp.ticket_type,
        tp.canal_de_entrada,
        tp.criticidade_ro,
        tp.group_name_ro,
        spoc.ts_termination_finished,
        CASE WHEN (CASE WHEN ddend.is_brz_holiday = 'Holiday' OR dayofweek(deadline_ticket_reparos) = 1 THEN date_add(deadline_ticket_reparos, 1) ELSE deadline_ticket_reparos END) >= TS_SOLVED THEN 1 ELSE 0 END as flag_sla_reparos,
        CASE WHEN date(spoc.ts_termination_finished) > ww_backlog.dt_end_6 THEN 0 ELSE 1 END as flag_sla_med,
        IF(dt.group_name = 'Rescisão por Inadimplência [OFF][POS][BACK]'
            AND tp.tipo_de_cliente LIKE '%proprietário%' AND tp.tipo_de_demanda IN ('demanda_de_processos')
            AND tp.tipo_de_processo IN ('despejo/fraude') AND dt.subject LIKE '%Rescisão do contrato%', 'despejo', NULL ) as tkt_despejo,
            tp.tipo_de_cliente,
        'Zendesk' as Platform,
        ROW_NUMBER() OVER (PARTITION BY tp.sk_ticket ORDER BY tp.ts_load DESC) AS rn
    FROM tp_dirty as tp
    LEFT JOIN spoc ON tp.sk_contract = spoc.sk_contract
    LEFT JOIN first_resolution AS fr on fr.last_agent_email = tp.last_agent_email
    LEFT JOIN dw_public.dim_date as ddend ON ddend.date = deadline_ticket_reparos
    LEFT JOIN datalake_date.workday_window AS ww_backlog ON date(tp.ts_started) = ww_backlog.dt_ref AND ww_backlog.id_city = 39
    LEFT JOIN dw_customer_support.dim_ticket as dt on dt.sk_ticket = tp.sk_ticket
),

solved_date AS (
    SELECT
        case_number,
        status,
        ts_event,
        da.email,
        -- Identifica a primeira ocorrência de Solved para pegar o agente
        ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY ts_event ASC) AS rn_first,
        -- Identifica a última ocorrência de Solved para pegar a data final
        ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY ts_event DESC) AS rn_last
    FROM status_historico
    LEFT JOIN dw_support_journey.dim_analyst as da
        ON da.sk_analyst = status_historico.id_owner AND da.is_current = true
    WHERE status IN ('Solved')
      -- NOVO FILTRO: Ignora atualizações se o caso já estava como 'Solved'
      AND COALESCE(status_anterior, '') != 'Solved'
),

-- SELECT * FROM solved_date
-- WHERE case_number = 1148264
solved_agg AS (
    SELECT
        f.case_number,
        f.email AS agent_first_solved,
        l.ts_event AS ts_last_solved
    FROM solved_date AS f
    INNER JOIN solved_date AS l ON f.case_number = l.case_number
    WHERE f.rn_first = 1 AND l.rn_last = 1
),

closed_agent_ranked AS (
    SELECT
        sh.case_number,
        da.email AS agent_closed,
        ROW_NUMBER() OVER (PARTITION BY sh.case_number ORDER BY sh.ts_event ASC) AS rn
    FROM status_historico AS sh
    LEFT JOIN dw_support_journey.dim_analyst AS da
        ON da.sk_analyst = sh.id_owner AND da.is_current = true
    WHERE sh.status = 'Closed'
),

closed_agent AS (
    SELECT case_number, agent_closed
    FROM closed_agent_ranked
    WHERE rn = 1
),

-- case_solve_bounds: só muda a linha do agent_solved (adiciona o join + COALESCE)
case_solve_bounds AS (
    SELECT
        c.case_number,
        CASE WHEN h.status IN ('Closed', 'Solved') THEN s.ts_last_solved ELSE NULL END AS ts_solved,
        c.closed_date,

        -- FIX: usa o agente do primeiro Solved; se não existir Solved, cai pro agente do Closed
        COALESCE(s.agent_first_solved, ca.agent_closed) AS agent_solved,

        CAST(c.created_date AS TIMESTAMP) - INTERVAL 3 HOURS AS ts_created,
        h.proximo_status,
        c.last_modified_date,
        CAST(CAST(c.created_date AS TIMESTAMP) - INTERVAL 3 HOURS AS DATE) AS dt_non_working_start,
        CAST(COALESCE(
            COALESCE(
                (CASE WHEN h.status IN ('Closed', 'Solved') THEN s.ts_last_solved END),
                CAST(c.closed_date AS TIMESTAMP)
            ),
            CURRENT_DATE
        ) AS DATE) AS dt_non_working_end
    FROM events_case_dirty AS c
    LEFT JOIN solved_agg AS s
        ON s.case_number = CAST(c.case_number AS INT)
    LEFT JOIN closed_agent AS ca
        ON ca.case_number = CAST(c.case_number AS INT)
    LEFT JOIN status_historico AS h
        ON h.case_number = CAST(c.case_number AS INT)
        AND h.rn = 1
),

exploded_case_non_working_days AS (
    SELECT
        csb.case_number,
        csb.ts_solved,
        csb.closed_date,
        csb.agent_solved,
        csb.ts_created,
        csb.proximo_status,
        csb.last_modified_date,
        EXPLODE_OUTER(
            CASE
                WHEN csb.dt_non_working_start <= csb.dt_non_working_end
                THEN SEQUENCE(csb.dt_non_working_start, csb.dt_non_working_end)
                ELSE ARRAY()
            END
        ) AS dt_interval
    FROM case_solve_bounds AS csb
),

case_bounds_with_non_working AS (
    SELECT
        ec.case_number,
        ec.ts_solved,
        ec.closed_date,
        ec.agent_solved,
        ec.ts_created,
        ec.proximo_status,
        ec.last_modified_date,
        COUNT(DISTINCT wh.dt_non_working) AS total_non_working
    FROM exploded_case_non_working_days AS ec
    LEFT JOIN weekends_and_holidays AS wh
        ON wh.dt_non_working = ec.dt_interval
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),

solved_final AS (
    SELECT DISTINCT
        case_number,
        ts_solved,
        closed_date,
        agent_solved,
        ts_created,
        proximo_status,
        total_non_working,
        ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY MAX(last_modified_date) DESC) AS rn
    FROM case_bounds_with_non_working
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),

cases_perspective AS (
    SELECT DISTINCT
        c.sk_case as id_case,
        CAST(c.case_number AS INT) as case_number,
        ec.contract_id__c as id_contract,
        du.sk_user,
        sla.ops as team,
        sla.Front_Or_Back,
        sla.Pre_Pos,
        sla.Area,
        sla.ops,
        c.status as case_status,
        c.subject as subject,
        c.record_type_name,
        c.developer_name as theme,
        c.type as case_type,
        CAST(c.ts_created AS TIMESTAMP) - INTERVAL 3 HOURS as ts_created,
        sd.ts_solved,
        CAST(c.ts_closed AS TIMESTAMP) - INTERVAL 3 HOURS as ts_closed,
        csat.sk_answer as sk_answer_csat,
        csat.ts_submitted as first_csat_ts_response,
        csat.satisfaction_score as first_csat_score,
        csat.respondent_comments as first_csat_comment,
        csat.is_solved,
        to_timestamp(c.ts_created) + (INTERVAL 1 MINUTE * fr.minutes_first_reply_time_business) AS data_first_reply,
        fr.minutes_first_reply_time_business AS minutes_first_reply_time_business,
        fr.minutes_first_reply_time_calendar as minutes_first_reply_time_calendar,
        fr.minutes_first_reply_open_time_business,
        fr.minutes_first_reply_open_time_calendar,
        fr.dt_first_open,
        fr.replies,
        datediff(to_timestamp(c.ts_closed), to_timestamp(c.ts_created)) as ldt_ticket,
        COALESCE(CAST(sla.sla_tgt AS INT),CAST(target_response_time_minutes / 1440.0 AS INT)) as sla_tgt,

        CASE
            WHEN COALESCE(sd.ts_solved,to_timestamp(c.ts_closed))  IS NULL THEN NULL
            WHEN (datediff(CAST(COALESCE(sd.ts_solved,to_timestamp(c.ts_closed)) AS DATE),CAST(to_timestamp(c.ts_created) AS DATE)) - COALESCE(sd.total_non_working, 0)) <=  COALESCE(CAST(sla.sla_tgt AS INT),CAST(target_response_time_minutes / 1440.0 AS INT)) THEN TRUE
            ELSE FALSE
        END as is_ticket_solved_within_sla,
        da.email as agent_email,
        COALESCE(d.email,sd.agent_solved) as agent_solved,
        CASE WHEN COALESCE(sd.agent_solved,da.email) ILIKE '%webhelp%' THEN 'webhelp'
             WHEN COALESCE(sd.agent_solved,da.email) ILIKE '%atento%' THEN 'atento'
             WHEN COALESCE(sd.agent_solved,da.email) ILIKE '%aec%' THEN 'aec'
             WHEN COALESCE(sd.agent_solved,da.email) ILIKE '%quintoandar%' THEN 'quintoandar'
             END as agent_organization,
        CASE WHEN COALESCE(sd.agent_solved,da.email) ILIKE '%webhelp%' THEN 'webhelp'
             WHEN COALESCE(sd.agent_solved,da.email) ILIKE '%atento%' THEN 'atento'
             WHEN COALESCE(sd.agent_solved,da.email) ILIKE '%aec%' THEN 'aec'
             WHEN COALESCE(sd.agent_solved,da.email) ILIKE '%quintoandar%' THEN 'quintoandar'
             END as agent_solved_organization,
        CASE WHEN c.record_type_name RLIKE '\\[NÃO UTILIZAR\\]' THEN 'Sim' ELSE 'Não' END as flag_teste,
        spoc.is_spoc_contract,
        spoc.spoc_wave,
        spoc.is_spoc_control_group,
        spoc.spoc_team,
        spoc.spoc_class,
        spoc.ts_termination_finished,
        CASE WHEN spoc.is_spoc_contract = TRUE AND spoc.spoc_class IN ('before_wave_6_lab_test', 'lab_test', 'rollout') THEN TRUE ELSE FALSE END as is_spoc_test,
        c.origin as case_origin,
        fr_res.first_resolution,
        CASE WHEN c.type LIKE '%Mediation%' THEN 'MED' END as off_area,
        CASE WHEN date(spoc.ts_termination_finished) > ww_backlog.dt_end_6 THEN 0 ELSE 1 END as flag_sla_med,
        ec.supplied_email,
        c.reason as case_reason,
        ec.omni_channel_queue__c as fila_omni_channel,
        ec.fr_case_reopen_count__c as reopens,
        ec.inspection_external_id__c as id_inspection,
        ec.property_id__c as id_house,
        ec.is_eviction__c as is_eviction,
        ec.is_pp_multi__c as is_pp_multi,
        ec.is_kirk__c as is_kirk,
        ec.is_high_value__c as is_high_value,
        ec.client_type__c as client_type,
        ec.reopened_at__c as dt_reopen,
        ec.last_customer_interaction__c as last_customer_interaction,
        ec.last_agent_interaction__c as last_agent_interaction,
        ec.last_front_comment_date__c as last_front_comment_date,
        ec.untreated_front_comment__c as untreated_front_comment,
        CASE WHEN c.type = 'Common' THEN 'Comum'
             WHEN c.type = 'Urgent' THEN 'Urgente'
             WHEN c.type = 'Emergency' THEN 'Emengencial' END as criticidade,
        ec.criticality_sla__c AS criticidade_sla,
        ec.sla_due_days__c as sla_target,
        ec.event_type  as event_type,
        ec.journey__c AS journey,
        ec.case_to_be_handled__c AS case_to_be_handled,
        ec.microtaxonomy__c as microtaxonomy_ra,
        ec.csat_survey_sent__c as csat_survey_sent,
        ec.repair_service_provider_date__c as dt_repair_service_provider_date,
        ec.ra_public_response_date__c as dt_ra_public_response_date,
        ec.ra_external_id__c as id_ra_external_id,
        ec.ra_creation_date__c as dt_ra_creation_date,
        ec.ra_resolved_issue__c as ra_resolved_issue,
        ec.ra_back_doing_business__c as ra_back_doing_business,
        ec.ra_rating__c as ra_rating,
        CASE WHEN ec.omni_channel_queue__c = 'Squad 7 - Mediação' THEN 'despejo' ELSE NULL END as tkt_despejo,
        'email' as channel,
        'SalesForce' as Platform,
        ROW_NUMBER() OVER (PARTITION BY c.sk_case ORDER BY to_timestamp(c.ts_last_modified) DESC) as rn

    FROM dw_cases_dirty as c
    LEFT JOIN events_case_dirty as ec on ec.id_record = c.sk_case and ec.rn = 1
    LEFT JOIN csat as csat on csat.sk_case = c.sk_case and csat.rn = 1
    LEFT JOIN sandbox.sla_target_salesforce as sla on sla.theme_type = COALESCE(CONCAT(c.developer_name, c.type), c.developer_name)
    LEFT JOIN dw_support_journey.dim_analyst as da on da.sk_analyst = c.sk_owner and da.is_current = true
    LEFT JOIN datalake_salesforce_clean.account as a on a.id_account = ec.id_account
    LEFT JOIN spoc ON CAST(ec.contract_id__c AS STRING) = CAST(spoc.sk_contract AS STRING)
    LEFT JOIN first_reply_final AS fr ON fr.id_case = c.sk_case
    LEFT JOIN first_resolution AS fr_res on fr_res.last_agent_email = da.email
    LEFT JOIN datalake_date.workday_window AS ww_backlog ON date(to_timestamp(c.ts_created)) = ww_backlog.dt_ref AND ww_backlog.id_city = 39
    LEFT JOIN solved_final as sd on sd.case_number = CAST(c.case_number AS INT) and sd.rn = 1
    LEFT JOIN datalake_salesforce_clean.events_case_member as cm on cm.case__c = c.sk_case AND type__c = 'Service requester'
    LEFT JOIN dw_public.dim_user as du on du.uuid_person = split(cm.external_id__c, '_')[2]
    LEFT JOIN dw_support_journey.dim_analyst AS d
    ON ec.resolved_by_analyst_id__c = SUBSTR(d.sk_analyst, 1, LENGTH(ec.resolved_by_analyst_id__c))

    WHERE c.sk_case NOT IN (SELECT id_record FROM deletados)
)


SELECT
    id_case,
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
    minutes_first_reply_time_calendar,
    minutes_first_reply_open_time_business,
    minutes_first_reply_open_time_calendar,
    subject,
    record_type_name,
    theme,
    case_type as theme_detail,
    NULL AS theme_recontact_flag_d4,
    NULL AS theme_recontact_flag_d0,
    sla_tgt,
    is_ticket_solved_within_sla,
    agent_email as last_agent_email,
    agent_organization as last_agent_organization,
    agent_solved as agent_solved,
    agent_solved_organization,
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
    ts_termination_finished,
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
    case_reason,
    dt_reopen,
    dt_first_open,
    last_front_comment_date,
    untreated_front_comment,
    last_agent_interaction,
    last_customer_interaction,
    journey as journey_csi,
    case_to_be_handled,
    microtaxonomy_ra,
    csat_survey_sent,
    dt_repair_service_provider_date,
    dt_ra_public_response_date,
    id_ra_external_id,
    dt_ra_creation_date,
    ra_resolved_issue,
    ra_back_doing_business,
    ra_rating,
    Platform,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM cases_perspective
WHERE rn = 1


UNION ALL

SELECT
    case_number as id_case,
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
    NULL AS resolution_survey,
    minutes_first_reply_time_business,
    NULL AS minutes_first_reply_time_calendar,
    NULL AS minutes_first_reply_open_time_business,
    NULL AS minutes_first_reply_open_time_calendar,
    subject,
    theme as record_type_name,
    theme,
    theme_detail,
    theme_recontact_flag_d4,
    theme_recontact_flag_d0,
    sla_tgt,
    is_ticket_solved_within_sla,
    last_agent_email,
    last_agent_organization,
    last_agent_email as agent_solved,
    last_agent_organization as agent_solved_organization,
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
    ts_termination_finished,
    flag_sla_med,
    tkt_despejo,
    first_resolution as first_resolution_last_agent,
    NULL AS id_inspection,
    NULL AS id_house,
    NULL AS is_eviction,
    NULL AS is_kirk,
    NULL AS is_high_value,
    NULL AS criticidade_sla,
    NULL AS event_type,
    NULL AS supplied_email,
    NULL AS case_reason,
    NULL AS dt_reopen,
    NULL AS dt_first_open,
    NULL AS last_front_comment_date,
    NULL AS untreated_front_comment,
    NULL AS last_agent_interaction,
    NULL AS last_customer_interaction,
    NULL AS  journey_csi,
    NULL AS case_to_be_handled,
    NULL AS microtaxonomy_ra,
    NULL AS csat_survey_sent,
    NULL AS dt_repair_service_provider_date,
    NULL AS dt_ra_public_response_date,
    NULL AS id_ra_external_id,
    NULL AS dt_ra_creation_date,
    NULL AS ra_resolved_issue,
    NULL AS ra_back_doing_business,
    NULL AS ra_rating,
    Platform,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM tickets_perspective

WHERE rn = 1
