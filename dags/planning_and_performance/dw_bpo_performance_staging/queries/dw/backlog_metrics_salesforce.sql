WITH

weekends_and_holidays AS (
    SELECT ad.date AS dt_non_working
    FROM datalake_quintoandar.aux_date AS ad
    WHERE ad.weekend = 'Weekend'
    UNION
    SELECT sch.dt_holiday AS dt_non_working
    FROM datalake_gsheets_clean.service_city_holidays AS sch
    WHERE sch.category = 'Nacional'
),

deletados as  (
    SELECT 
        id_record,
        event_type
    FROM datalake_salesforce_clean.events_case
    WHERE event_type IN ('DELETE')
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
        dit.team AS spoc_team,
        dit.has_mediation,
        dit.has_ac_repairs,
        dit.dt_inspection,
        CASE
            WHEN
                ft.ts_termination_request < DATE('2025-05-22')
                AND ft.is_spoc_contract = TRUE
                AND (ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL)
                THEN 'before_wave_6_lab_test'
            WHEN
                ft.ts_termination_request < DATE('2025-05-22')
                AND ft.is_spoc_contract = TRUE
                AND ft.is_spoc_control_group = TRUE
                THEN 'before_wave_6_lab_control'
            WHEN
                ft.ts_termination_request >= DATE('2025-05-22')
                AND ft.is_spoc_contract = TRUE
                AND (ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL)
                AND (dit.team IN ('ROLLOUT', 'BAU_LONG_LDT', 'BAU_SHORT_LDT') OR dit.team IS NULL)
                THEN 'rollout'
            WHEN
                ft.ts_termination_request >= DATE('2025-05-22')
                AND ft.is_spoc_contract = TRUE
                AND (ft.is_spoc_control_group = FALSE OR ft.is_spoc_control_group IS NULL)
                AND dit.team = 'LAB'
                THEN 'lab_test'
            WHEN
                ft.ts_termination_request >= DATE('2025-05-22')
                AND ft.is_spoc_contract = TRUE
                AND ft.is_spoc_control_group = TRUE
                THEN 'lab_control'
        END AS spoc_class
    FROM dw_offboarding.fact_terminations AS ft
    LEFT JOIN dw_offboarding.dim_termination AS dit
        ON ft.sk_termination = dit.sk_termination
    WHERE ft.ts_termination_canceled IS NULL AND ft.ts_termination_request >= DATE('2025-01-01')
),

caso_pai_chaves AS (
  SELECT DISTINCT 
    id_record, 
    type AS parent_case_type,
    CAST(created_date AS TIMESTAMP) - INTERVAL 3 HOURS AS sync_date__c
FROM datalake_salesforce_clean.events_case 
WHERE type IN ('Key Logistics For Rent Onboarding', 'Key Logistics For Rent Offboarding')
),

vistoria_offboarding AS (
    SELECT 
        ft.sk_contract,
        dit.dt_inspection,
        ROW_NUMBER() OVER(PARTITION BY ft.sk_contract ORDER BY ft.ts_termination_request DESC) as rn
    FROM dw_offboarding.fact_terminations AS ft
    LEFT JOIN dw_offboarding.dim_termination dit
        ON ft.sk_termination = dit.sk_termination
    WHERE ft.ts_termination_canceled IS NULL
),

first_open as (
    SELECT 
        cast(e.case_number as int) as case_number,
        id_record as sk_case, 
        MIN(CAST(last_modified_date AS TIMESTAMP) - INTERVAL 3 HOURS) AS dt_first_open
    FROM datalake_salesforce_clean.events_Case AS E
    LEFT JOIN dw_support_journey.fact_requests as fr on fr.sk_case = e.id_record and fr.is_current = true 
    WHERE E.status not in ('SelfService','Solved','Closed')
    AND fr.record_type_name in ('Solicitação de Reparos','Reparos Ongoing')
    GROUP BY 1,2
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
        CAST(SUM(GREATEST(0, minutes_calc)) AS INT) AS minutes_first_reply_time_business,
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
    FROM datalake_salesforce_clean.events_case 
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
    FROM datalake_salesforce_clean.events_case  AS c
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

events_case as (
SELECT
id_record, 
contract_id__c,
is_pp_multi__c,
id_parent,
type,
origin,
supplied_email,
omni_channel_queue__c,
resolved_by_analyst_id__c, 
ROW_NUMBER() OVER (PARTITION BY id_record ORDER BY last_modified_date DESC) AS rn

FROM datalake_salesforce_clean.events_case as ec  
),

cases_perspective AS (
    SELECT DISTINCT
        CAST(c.case_number AS INT) AS case_number,
        ec.contract_id__c AS id_contract,
        du.sk_user,
        sla.ops AS team,
        sla.front_or_back,
        sla.pre_pos,
        sla.area,
        c.subject,
        c.record_type_name,
        c.developer_name AS theme,
        c.type AS case_type,
        dt_first_open,
        CASE WHEN c.record_type_name in ('Solicitação de Reparos','Reparos Ongoing') THEN dt_first_open ELSE 
        CAST(c.ts_created AS TIMESTAMP) - INTERVAL 3 HOURS END AS ts_created,
        sd.ts_solved,
        CAST(c.ts_closed AS TIMESTAMP) - INTERVAL 3 HOURS as ts_closed,
        c.status AS case_status,
        fr.minutes_first_reply_time_business,
        fr.replies,
        COALESCE(d.email,sd.agent_solved,da.email) AS agent_email,
        da.sk_analyst as id_user_salesforce,
        spoc.is_spoc_contract,
        spoc.spoc_wave,
        spoc.is_spoc_control_group,
        spoc.spoc_team,
        spoc.spoc_class,
        ec.is_pp_multi__c AS is_pp_multi,
        ec.origin AS case_origin,
        ec.supplied_email,
        ec.omni_channel_queue__c AS omni_channel_queue,
        'SalesForce' AS platform,
        COALESCE(CAST(bc.Timestamp AS TIMESTAMP), sd.ts_solved, CAST(c.ts_closed AS TIMESTAMP) - INTERVAL 3 HOURS) AS ts_solved_closed,
        DATEDIFF(CAST(COALESCE(CAST(bc.Timestamp AS TIMESTAMP),sd.ts_solved, CAST(c.ts_closed AS TIMESTAMP) - INTERVAL 3 HOURS) AS DATE),CAST(c.ts_created AS TIMESTAMP) - INTERVAL 3 HOURS)
            AS ldt_ticket,
        COALESCE(CAST(sla.sla_tgt AS INT), CAST(target_response_time_minutes / 1440.0 AS INT)) AS sla_tgt,
        CASE
            WHEN
                DATEDIFF(COALESCE(CAST(bc.Timestamp AS TIMESTAMP),sd.ts_solved, CAST(c.ts_closed AS TIMESTAMP) - INTERVAL 3 HOURS), CAST(c.ts_created AS TIMESTAMP) - INTERVAL 3 HOURS)
                > COALESCE(CAST(sla.sla_tgt AS INT), CAST(target_response_time_minutes / 1440.0 AS INT))
                AND COALESCE(CAST(bc.Timestamp AS TIMESTAMP),sd.ts_solved, CAST(c.ts_closed AS TIMESTAMP) - INTERVAL 3 HOURS) IS NOT NULL
                THEN FALSE
            WHEN
                DATEDIFF(COALESCE(CAST(bc.Timestamp AS TIMESTAMP),sd.ts_solved, CAST(c.ts_closed AS TIMESTAMP) - INTERVAL 3 HOURS), CAST(c.ts_created AS TIMESTAMP) - INTERVAL 3 HOURS)
                <= COALESCE(CAST(sla.sla_tgt AS INT), CAST(target_response_time_minutes / 1440.0 AS INT))
                AND COALESCE(CAST(bc.Timestamp AS TIMESTAMP),sd.ts_solved, CAST(c.ts_closed AS TIMESTAMP) - INTERVAL 3 HOURS) IS NOT NULL
                THEN TRUE
        END AS is_ticket_solved_within_sla,
        CASE
            WHEN da.email LIKE '%webhelp%' THEN 'webhelp'
            WHEN da.email LIKE '%atento%' THEN 'atento'
            WHEN da.email LIKE '%aec%' THEN 'aec'
        END AS agent_organization,
        CASE WHEN c.record_type_name RLIKE '\\[NÃO UTILIZAR\\]' THEN 'Sim' ELSE 'Não' END AS flag_teste,
        (
            spoc.is_spoc_contract = TRUE
            AND spoc.spoc_class IN ('before_wave_6_lab_test', 'lab_test', 'rollout')
        ) AS is_spoc_test,
        CASE WHEN c.type LIKE '%Mediation%' THEN 'MED' END AS off_area,
        CASE
            WHEN
                COALESCE(CAST(spoc.ts_termination_finished AS DATE), CURRENT_DATE()) >= ww_backlog.dt_end_6
                THEN 0
            ELSE 1
        END AS flag_sla_med, 
        parent_case_type
    FROM dw_support_journey.fact_requests AS c
    LEFT JOIN dw_support_journey.dim_analyst as da on da.sk_analyst = c.sk_owner and da.is_current = true
    LEFT JOIN events_case as ec on ec.id_record = c.sk_case and ec.rn = 1 
    LEFT JOIN
        sandbox.sla_target_salesforce AS sla
        ON sla.theme_type = COALESCE(CONCAT(c.developer_name, ec.type), c.developer_name)
    LEFT JOIN spoc ON CAST(ec.contract_id__c AS STRING) = CAST(spoc.sk_contract AS STRING)
    LEFT JOIN first_reply_final AS fr ON CAST(fr.case_number AS INT) = CAST(c.case_number AS INT)
    LEFT JOIN
        datalake_date.workday_window AS ww_backlog
        ON CAST(CAST(c.ts_created AS TIMESTAMP) - INTERVAL 3 HOURS AS DATE)  = ww_backlog.dt_ref AND ww_backlog.id_city = 39
    LEFT JOIN solved_final AS sd ON CAST(sd.case_number AS INT) = CAST(c.case_number AS INT) AND sd.rn = 1
    LEFT JOIN
        datalake_salesforce_clean.events_case_member AS ecm
        ON c.sk_case = ecm.case__c AND ecm.type__c = 'Service requester'
    LEFT JOIN dw_public.dim_user AS du ON du.uuid_person = SPLIT(ecm.external_id__c, '_')[2]
    LEFT JOIN dw_support_journey.dim_analyst AS d
    ON ec.resolved_by_analyst_id__c = SUBSTR(d.sk_analyst, 1, LENGTH(ec.resolved_by_analyst_id__c))
    LEFT JOIN caso_pai_chaves AS pai ON pai.id_record = ec.id_parent
    LEFT JOIN sandbox.casos_bug_chaves as bc on bc.case_number = c.case_number 
    LEFT JOIN vistoria_offboarding AS vo ON CAST(vo.sk_contract AS STRING) = CAST(ec.contract_id__c AS STRING) AND vo.rn = 1
    WHERE c.sk_case NOT IN (SELECT id_record FROM deletados)
    and c.is_current = true
),


calendario AS (
    SELECT CAST(date_sequence AS DATE) AS dia
    FROM (
        SELECT EXPLODE(SEQUENCE(DATE('2024-01-01'), CURRENT_DATE())) AS date_sequence
    ) AS date_exploded
),

final_table AS (
    SELECT
        cp.*,
        c.dia AS date_reference
    FROM calendario AS c
    CROSS JOIN cases_perspective AS cp
    WHERE
        1 = 1
        AND c.dia <= CURRENT_DATE()
        AND c.dia >= CAST(cp.ts_created AS DATE)
        AND (cp.ts_solved_closed IS NULL OR c.dia <= CAST(cp.ts_solved_closed AS DATE))
       
),

exploded_backlog AS (
    SELECT
        case_number,
        id_user_salesforce AS id_agent,
        sk_user,
        sla_tgt AS sla_target,
        agent_email,
        case_origin AS origin,
        ts_created,
        ts_closed,
        ts_solved_closed,
        DATE(ts_solved_closed) AS dt_final,
        EXPLODE(
            SEQUENCE(
                DATE(ts_created),
                DATE(COALESCE(ts_solved_closed, NOW()))
            )
        ) AS dt_interval
    FROM cases_perspective
),

-- EMR-safe replacement for the BETWEEN range join: exploded_backlog already
-- holds every day in [DATE(ts_created), dt_interval], so flagging each
-- non-working day and taking a running SUM equals the old range count.
marked_backlog AS (
    SELECT
        eb.case_number,
        eb.dt_interval,
        MAX(
            CASE
                WHEN nw.dt_non_working IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS is_non_working
    FROM exploded_backlog AS eb
    LEFT JOIN weekends_and_holidays AS nw
        ON nw.dt_non_working = eb.dt_interval
    GROUP BY
        eb.case_number,
        eb.dt_interval
),

days_off AS (
    SELECT
        case_number,
        dt_interval,
        SUM(is_non_working) OVER (
            PARTITION BY case_number
            ORDER BY dt_interval
        ) AS days_off
    FROM marked_backlog
)

SELECT DISTINCT
    final_table.date_reference,
    final_table.case_number,
    final_table.ts_created AS ts_started,
    final_table.id_contract AS sk_contract,
    final_table.ts_solved_closed,
    final_table.dt_first_open,
    final_table.sk_user,
    final_table.area AS last_area,
    final_table.front_or_back,
    final_table.omni_channel_queue AS last_department,
    final_table.minutes_first_reply_time_business,
    final_table.subject,
    final_table.theme,
    final_table.case_type AS theme_detail,
    final_table.sla_tgt,
    final_table.replies,
    final_table.is_ticket_solved_within_sla,
    final_table.agent_email AS last_agent_email,
    final_table.agent_organization AS last_agent_organization,
    final_table.is_spoc_test,
    final_table.is_pp_multi,
    final_table.case_origin AS canal_de_entrada,
    final_table.platform,
    final_table.supplied_email,
    final_table.omni_channel_queue AS fila_omni_channel,
    final_table.record_type_name,
    CASE
        WHEN DATE(final_table.date_reference) < CAST(final_table.ts_solved AS DATE) THEN NULL ELSE final_table.ts_solved
    END AS ts_solved,
    CASE
        WHEN DATE(final_table.date_reference) < CAST(final_table.ts_closed AS DATE) THEN NULL ELSE final_table.ts_closed
    END AS ts_closed,
    CASE
        WHEN
            final_table.date_reference
            = COALESCE(CAST(final_table.ts_solved AS DATE), CAST(final_table.ts_closed AS DATE))
            THEN final_table.case_status
        ELSE 'open'
    END AS case_status,
    DATEDIFF(e.dt_interval, CAST(e.ts_created AS DATE)) - COALESCE(d.days_off, 0) AS days_worked,
    DATEDIFF(e.dt_interval, CAST(e.ts_created AS DATE)) AS days_worked_with_days_offs,
    COALESCE(d.days_off, 0) AS days_off,
CASE 
            -- Onboarding: <= 1 dia útil (descontando fins de semana e feriados)
            WHEN (final_table.parent_case_type = 'Key Logistics For Rent Onboarding' OR final_table.case_type = 'Key Logistics For Rent Onboarding') AND CAST(final_table.ts_created AS DATE) >= DATE '2026-06-01' THEN 
                CASE WHEN DATEDIFF(final_table.date_reference, CAST(final_table.ts_created AS DATE)) - COALESCE(d.days_off, 0) <= 1 THEN 1 ELSE 0 END

            -- Offboarding: <= 3 dias úteis (descontando fins de semana e feriados)
            WHEN (final_table.parent_case_type = 'Key Logistics For Rent Offboarding' OR final_table.case_type = 'Key Logistics For Rent Offboarding') AND CAST(final_table.ts_created AS DATE) >= DATE '2026-06-01' THEN 
                CASE WHEN DATEDIFF(final_table.date_reference, CAST(final_table.ts_created AS DATE)) - COALESCE(d.days_off, 0) <= 3 THEN 1 ELSE 0 END
                
            -- Regra Geral de SLA
            ELSE 
                CASE WHEN DATEDIFF(final_table.date_reference, CAST(final_table.ts_created AS DATE)) - COALESCE(d.days_off, 0) <= COALESCE(e.sla_target, 0) THEN 1 ELSE 0 END 
        END AS is_backlog_in_time,

        CASE WHEN (UNIX_TIMESTAMP(COALESCE(final_table.ts_solved_closed, DATE_TRUNC('day', CURRENT_TIMESTAMP()))) - UNIX_TIMESTAMP(final_table.ts_created)) / 3600 > 48 THEN 1 ELSE 0 END AS is_backlog_not_in_time_3d,
        
        CASE 
            -- Onboarding: > 1 dia útil (descontando fins de semana e feriados)
            WHEN (final_table.parent_case_type = 'Key Logistics For Rent Onboarding' OR final_table.case_type = 'Key Logistics For Rent Onboarding') AND CAST(final_table.ts_created AS DATE) >= DATE '2026-06-01' THEN 
                CASE WHEN DATEDIFF(final_table.date_reference, CAST(final_table.ts_created AS DATE)) - COALESCE(d.days_off, 0) > 1 THEN 1 ELSE 0 END

            -- Offboarding: > 3 dias úteis (descontando fins de semana e feriados)
            WHEN (final_table.parent_case_type = 'Key Logistics For Rent Offboarding' OR final_table.case_type = 'Key Logistics For Rent Offboarding') AND CAST(final_table.ts_created AS DATE) >= DATE '2026-06-01' THEN 
                CASE WHEN DATEDIFF(final_table.date_reference, CAST(final_table.ts_created AS DATE)) - COALESCE(d.days_off, 0) > 3 THEN 1 ELSE 0 END
                
            -- Regra Geral de SLA
            ELSE 
                CASE WHEN DATEDIFF(final_table.date_reference, CAST(final_table.ts_created AS DATE)) - COALESCE(d.days_off, 0) > COALESCE(e.sla_target, 0) THEN 1 ELSE 0 END 
        END AS is_backlog_not_in_time,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM final_table
LEFT JOIN days_off AS d ON final_table.case_number = d.case_number AND final_table.date_reference = d.dt_interval
LEFT JOIN
    exploded_backlog AS e
    ON final_table.case_number = e.case_number AND final_table.date_reference = e.dt_interval
