WITH milestones AS (
    SELECT
        id_case,
        target_response_in_days,
        ROW_NUMBER() OVER (PARTITION BY id_case ORDER BY ts_last_modified ASC) AS rn

    FROM datalake_salesforce_clean.case_milestones

-- WHERE id_case = '500bL00000YFBysQAH'

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

record_types AS (
    SELECT
        rt.id_record_type,
        rt.ts_last_modified,
        rt.record_type_name,
        rt.developer_name
    FROM (
        SELECT
            id_record_type,
            ts_last_modified,
            record_type_name,
            developer_name,
            ROW_NUMBER() OVER (
                PARTITION BY id_record_type
                ORDER BY CAST(ts_last_modified AS TIMESTAMP) DESC
            ) AS rn
        FROM datalake_salesforce_clean.record_types
    ) AS rt
    WHERE rt.rn = 1
),

first_reply_sf AS (
    SELECT
        c.id_case,
        c.case_number,
        CAST(
            (
                CAST(MIN(CAST(e.ts_message AS TIMESTAMP) - INTERVAL '7' HOUR) AS LONG)
                - CAST((CAST(c.ts_created AS TIMESTAMP) - INTERVAL '7' HOUR) AS LONG)
            )
            / 60 AS INT
        ) AS minutes_first_reply_time_business,
        MIN(CAST(e.ts_message AS TIMESTAMP) - INTERVAL '7' HOUR) AS ts_first_reply,
        -- Spark calcula a diferença de minutos transformando a subtração em segundos e dividindo por 60
        COUNT(DISTINCT e.ts_message) AS replies
    FROM datalake_salesforce_clean.cases AS c
    INNER JOIN datalake_salesforce_clean.email_message AS e
        ON c.id_case = e.id_parent
    WHERE
        e.ts_message IS NOT NULL
        AND e.is_incoming = FALSE
    GROUP BY
        c.id_case,
        c.case_number,
        c.ts_created
),

status_historico AS (
    SELECT
        CAST(case_number AS INT) AS case_number,
        status,
        -- No Spark, a subtração de horas é feita via INTERVAL
        CAST(last_modified_date AS TIMESTAMP) - INTERVAL 3 HOURS AS ts_event,
        ROW_NUMBER()
            OVER (PARTITION BY CAST(case_number AS INT) ORDER BY CAST(last_modified_date AS TIMESTAMP) DESC)
            AS rn,
        -- Pega o próximo status que o caso assumiu cronologicamente
        COALESCE(
            LEAD(status) OVER (
                PARTITION BY CAST(case_number AS INT)
                ORDER BY CAST(last_modified_date AS TIMESTAMP) ASC
            ),
            status
        ) AS proximo_status
    FROM datalake_salesforce_clean.events_case
),

solved_date AS (
    -- Simplificado para o padrão do Spark: Primeiro ordena os eventos e depois qualifica
    SELECT
        case_number,
        status,
        ts_event,
        ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY ts_event ASC) AS rn
    FROM status_historico
    WHERE status = 'Solved'
),

solved_final AS (
    SELECT DISTINCT
        c.case_number,
        c.closed_date,
        h.proximo_status,
        CASE WHEN h.proximo_status IS NULL OR h.proximo_status IN ('Closed', 'Solved') THEN s.ts_event END AS ts_solved,
        CAST(c.created_date AS TIMESTAMP) - INTERVAL 3 HOURS AS ts_created,
        ROW_NUMBER() OVER (PARTITION BY c.case_number ORDER BY c.last_modified_date DESC) AS rn

    FROM datalake_salesforce_clean.events_case AS c
    -- Filtramos apenas o primeiro registro de 'Solved' na junção (rn_primeiro_solved = 1)
    LEFT JOIN solved_date AS s ON s.case_number = CAST(c.case_number AS INT) AND s.rn = 1
    LEFT JOIN status_historico AS h ON h.case_number = CAST(c.case_number AS INT) AND h.rn = 1

),


cases_perspective AS (
    SELECT DISTINCT
        CAST(c.case_number AS INT) AS case_number,
        c.contract_id__c AS id_contract,
        du.sk_user,
        sla.ops AS team,
        sla.front_or_back,
        sla.pre_pos,
        sla.area,
        c.subject,
        rt.record_type_name,
        rt.developer_name AS theme,
        c.type AS case_type,
        CAST(c.created_date AS TIMESTAMP) AS ts_created,
        sd.ts_solved,
        CAST(c.closed_date AS TIMESTAMP) AS ts_closed,
        c.status AS case_status,
        fr.minutes_first_reply_time_business,
        fr.replies,
        u.email AS agent_email,
        u.id_user_salesforce,
        spoc.is_spoc_contract,
        spoc.spoc_wave,
        spoc.is_spoc_control_group,
        spoc.spoc_team,
        spoc.spoc_class,
        c.is_pp_multi__c AS is_pp_multi,
        c.origin AS case_origin,
        c.supplied_email,
        c.omni_channel_queue__c AS omni_channel_queue,
        'SalesForce' AS platform,
        COALESCE(sd.ts_solved, CAST(c.closed_date AS TIMESTAMP)) AS ts_solved_closed,
        DATEDIFF(COALESCE(sd.ts_solved, CAST(c.closed_date AS TIMESTAMP)), CAST(c.created_date AS TIMESTAMP))
            AS ldt_ticket,
        COALESCE(CAST(sla.sla_tgt AS INT), CAST(cm.target_response_in_days AS INT)) AS sla_tgt,
        CASE
            WHEN
                DATEDIFF(COALESCE(sd.ts_solved, CAST(c.closed_date AS TIMESTAMP)), CAST(c.created_date AS TIMESTAMP))
                > COALESCE(CAST(sla.sla_tgt AS INT), CAST(cm.target_response_in_days AS INT))
                AND COALESCE(sd.ts_solved, CAST(c.closed_date AS TIMESTAMP)) IS NOT NULL
                THEN FALSE
            WHEN
                DATEDIFF(COALESCE(sd.ts_solved, CAST(c.closed_date AS TIMESTAMP)), CAST(c.created_date AS TIMESTAMP))
                <= COALESCE(CAST(sla.sla_tgt AS INT), CAST(cm.target_response_in_days AS INT))
                AND COALESCE(sd.ts_solved, CAST(c.closed_date AS TIMESTAMP)) IS NOT NULL
                THEN TRUE
        END AS is_ticket_solved_within_sla,
        CASE
            WHEN u.email LIKE '%webhelp%' THEN 'webhelp'
            WHEN u.email LIKE '%atento%' THEN 'atento'
            WHEN u.email LIKE '%aec%' THEN 'aec'
        END AS agent_organization,
        CASE WHEN rt.record_type_name RLIKE '\\[NÃO UTILIZAR\\]' THEN 'Sim' ELSE 'Não' END AS flag_teste,
        (
            spoc.is_spoc_contract = TRUE
            AND spoc.spoc_class IN ('before_wave_6_lab_test', 'lab_test', 'rollout')
        ) AS is_spoc_test,
        CASE WHEN c.type LIKE '%Mediation%' THEN 'MED' END AS off_area,
        CASE
            WHEN
                COALESCE(CAST(spoc.ts_termination_finished AS DATE), CURRENT_DATE()) >= ww_backlog.dt_end_9
                THEN 0
            ELSE 1
        END AS flag_sla_med,
        ROW_NUMBER() OVER (PARTITION BY c.case_number ORDER BY c.last_modified_date DESC) AS rn
    FROM datalake_salesforce_clean.events_case AS c
    LEFT JOIN record_types AS rt ON c.id_record_type = rt.id_record_type
    LEFT JOIN
        sandbox.sla_target_salesforce AS sla
        ON sla.theme_type = COALESCE(CONCAT(rt.developer_name, c.type), rt.developer_name)
    LEFT JOIN datalake_salesforce_clean.users AS u ON c.id_owner = u.id_user_salesforce
    LEFT JOIN spoc ON CAST(c.contract_id__c AS STRING) = CAST(spoc.sk_contract AS STRING)
    LEFT JOIN first_reply_sf AS fr ON CAST(fr.case_number AS INT) = CAST(c.case_number AS INT)
    LEFT JOIN
        datalake_date.workday_window AS ww_backlog
        ON CAST(c.created_date AS DATE) = ww_backlog.dt_ref AND ww_backlog.id_city = 39
    LEFT JOIN solved_final AS sd ON CAST(sd.case_number AS INT) = CAST(c.case_number AS INT) AND sd.rn = 1
    LEFT JOIN
        datalake_salesforce_clean.events_case_member AS ecm
        ON c.id_record = ecm.case__c AND ecm.type__c = 'Service requester'
    LEFT JOIN dw_public.dim_user AS du ON du.uuid_person = SPLIT(ecm.external_id__c, '_')[2]
    LEFT JOIN milestones AS cm ON c.id_record = cm.id_case AND cm.rn = 1

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
        AND cp.rn = 1
),

weekends_and_holidays AS (
    SELECT ad.date AS dt_non_working
    FROM datalake_quintoandar.aux_date AS ad
    WHERE ad.weekend = 'Weekend'
    UNION
    SELECT sch.dt_holiday AS dt_non_working
    FROM datalake_gsheets_clean.service_city_holidays AS sch
    WHERE sch.category = 'Nacional'
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
    WHERE rn = 1
),

days_off AS (
    SELECT
        eb.case_number,
        eb.dt_interval,
        COUNT(*) AS days_off
    FROM exploded_backlog AS eb
    INNER JOIN weekends_and_holidays AS nw
        ON nw.dt_non_working BETWEEN CAST(eb.ts_created AS DATE) AND eb.dt_interval
    GROUP BY eb.case_number, eb.dt_interval
)

SELECT DISTINCT
    final_table.date_reference,
    final_table.case_number,
    final_table.ts_created AS ts_started,
    final_table.id_contract AS sk_contract,
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
        WHEN DATEDIFF(e.dt_interval, CAST(e.ts_created AS DATE)) - COALESCE(d.days_off, 0) <= e.sla_target THEN 1
        ELSE 0
    END AS is_backlog_in_time,
    CASE
        WHEN DATEDIFF(e.dt_interval, CAST(e.ts_created AS DATE)) - COALESCE(d.days_off, 0) > e.sla_target THEN 1
        ELSE 0
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
