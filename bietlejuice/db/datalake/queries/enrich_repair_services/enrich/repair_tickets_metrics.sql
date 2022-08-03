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
tickets AS (
    SELECT
        rt.id_ticket AS id_ticket_cx,
        rts.id_ticket,
        rts.id_ticket_referential,
        rts.id_contract,
        rts.id_provider,
        rts.id_zendesk_provider,
        rts.request_type,
        rts.status,
        DATEDIFF(rts.dt_created,rt.dt_created) AS ldt_opening,
        DATEDIFF(rts.dt_budget_request_submitted,rts.dt_created) AS ldt_budget_submission,
        DATEDIFF(rts.dt_visit_schedule,rts.dt_submission_visit_scheduling_team) AS ldt_visit_scheduling,
        DATEDIFF(rts.dt_visit,rts.dt_visit_schedule) AS ldt_start_visit,
        DATEDIFF(rts.dt_visit_took_place,rts.dt_visit) AS ldt_technical_visit,
        DATEDIFF(rts.dt_budget_submission_by_ps,rts.dt_budget_request_submitted) AS ldt_budget_receipt,
        DATEDIFF(rts.dt_budget_submission_to_cx,rts.dt_budget_submission_by_ps) AS ldt_sent_to_cx,
        DATEDIFF(rts.dt_cx_approval_communication_for_ps,rts.dt_budget_submission_to_cx) AS ldt_cx_return_with_approval,
        DATEDIFF(rts.dt_contact_scheduling_service_started,rts.dt_cx_approval_communication_for_ps) AS ldt_start_service_scheduling,
        DATEDIFF(rts.dt_service_appointment,rts.dt_contact_scheduling_service_started) AS ldt_service_scheduling,
        DATEDIFF(rts.dt_service_started,rts.dt_service_appointment) AS ldt_start_execution,
        DATEDIFF(rts.dt_repair_completion,rts.dt_service_started) AS ldt_execution_repair,
        DATEDIFF(rts.dt_repair_completion,rts.dt_cx_approval_communication_for_ps) AS ldt_execution,
        DATEDIFF(rts.dt_repair_completion,rt.dt_created) AS frt,
        rts.repair_front,
        rts.group_name,
        CASE
            WHEN rts.status NOT IN ('hold', 'open', 'pending')
                AND rts.dt_cx_disapproval_returned IS NULL
                AND rts.dt_cx_approval_communication_for_ps IS NULL
                THEN True
            ELSE False
        END AS is_cx_disapproval,
        CASE
            WHEN rts.dt_budget_submission_to_cx IS NOT NULL THEN True
            ELSE False
        END AS is_budget_submission_to_cx,
        rts.is_budget_approved,
        rts.is_budget_disapproved,
        rts.dt_budget_submission_to_cx,
        rts.dt_cx_disapproval_returned,
        rts.dt_cx_approval_communication_for_ps,
        rts.dt_budget_request_submitted,
        rts.dt_budget_submission_by_ps,
        rts.dt_repair_completion,
        rts.dt_service_appointment,
        rts.dt_service_started,
        rt.dt_created AS dt_cx_created,
        rts.dt_created
    FROM
        datalake_repair_services.repair_tickets rt
    LEFT JOIN
        datalake_repair_services.repair_tickets rts
            ON rts.id_ticket_cx = rt.id_ticket
),
sla_budget_sent AS (
    SELECT
        id_ticket_cx,
        id_ticket,
        COUNT(1) AS days_off
    FROM
        tickets AS t
    JOIN
        weekends_and_holidays AS wh
            ON wh.dt_non_working BETWEEN t.dt_created AND t.dt_budget_request_submitted
    GROUP BY 1,2
),
sla_budgeting AS (
    SELECT
        id_ticket_cx,
        id_ticket,
        COUNT(1) AS days_off
    FROM
        tickets AS t
    JOIN
        weekends_and_holidays AS wh
            ON wh.dt_non_working BETWEEN t.dt_budget_request_submitted AND t.dt_budget_submission_by_ps
    GROUP BY 1,2
),
sla_execution AS (
    SELECT
        id_ticket_cx,
        id_ticket,
        COUNT(1) AS days_off
    FROM
        tickets AS t
    JOIN
        weekends_and_holidays AS wh
            ON wh.dt_non_working BETWEEN t.dt_cx_approval_communication_for_ps AND t.dt_repair_completion
    GROUP BY 1,2
),
budgeting AS (
    WITH follow_up_tickets AS (
        SELECT
            t.id_ticket,
            t.id_ticket_referential,
            CASE
                WHEN t.is_budget_approved IS TRUE THEN t.id_ticket
                ELSE NULL
            END AS id_ticket_approved,
            CASE
                WHEN t.is_budget_disapproved IS TRUE THEN t.id_ticket
                ELSE NULL
            END AS id_ticket_declined,
            CASE
                WHEN t.is_budget_submission_to_cx IS TRUE THEN t.id_ticket
                ELSE NULL
            END AS id_ticket_submitted,
            CASE
                WHEN t.is_cx_disapproval IS NOT TRUE
                    AND t.is_budget_approved IS NOT TRUE
                    AND t.is_budget_disapproved IS NOT TRUE
                    AND t.is_budget_submission_to_cx IS NOT TRUE
                    THEN t.id_ticket
                ELSE NULL
            END AS id_ticket_in_progress,
            t.is_cx_disapproval,
            t.is_budget_submission_to_cx,
            t.is_budget_approved,
            t.is_budget_disapproved
        FROM
            tickets t
    )
    SELECT
        fut.id_ticket_referential,
        CASE
            WHEN COUNT(fut.id_ticket_referential) = SUM(CAST(fut.is_cx_disapproval AS SMALLINT)) THEN NULL
            WHEN SUM(CAST(fut.is_budget_approved AS SMALLINT)) > 0
                THEN FIRST(fut.id_ticket_approved) IGNORE NULLS
            WHEN SUM(CAST(fut.is_budget_disapproved AS SMALLINT)) > 0
                AND SUM(CAST(fut.is_budget_approved AS SMALLINT)) = 0
                THEN FIRST(fut.id_ticket_declined) IGNORE NULLS
            WHEN SUM(CAST(fut.is_budget_submission_to_cx AS SMALLINT)) > 0
                AND SUM(CAST(fut.is_budget_disapproved AS SMALLINT)) = 0
                AND SUM(CAST(fut.is_budget_approved AS SMALLINT)) = 0
                THEN FIRST(fut.id_ticket_submitted) IGNORE NULLS
            ELSE FIRST(fut.id_ticket_in_progress) IGNORE NULLS
        END AS id_ticket_follow_up,
        CASE
            WHEN COUNT(fut.id_ticket_referential) = SUM(CAST(fut.is_cx_disapproval AS SMALLINT)) THEN 'Orçamento Cancelado'
            WHEN SUM(CAST(fut.is_budget_approved AS SMALLINT)) > 0 THEN 'Orçamento Aprovado'
            WHEN SUM(CAST(fut.is_budget_disapproved AS SMALLINT)) > 0
                AND SUM(CAST(fut.is_budget_approved AS SMALLINT)) = 0
                THEN 'Orçamento Recusado'
            WHEN SUM(CAST(fut.is_budget_submission_to_cx AS SMALLINT)) > 0
                AND SUM(CAST(fut.is_budget_disapproved AS SMALLINT)) = 0
                AND SUM(CAST(fut.is_budget_approved AS SMALLINT)) = 0
                THEN 'Aguardando Aprovação'
            ELSE 'Orçamento em andamento'
        END AS budgeting_status
    FROM
        follow_up_tickets fut
    GROUP BY 1
)
SELECT
    t.id_ticket,
    t.id_ticket_cx,
    t.id_ticket_referential,
    b.id_ticket_follow_up,
    t.id_contract,
    t.id_provider,
    t.id_zendesk_provider,
    t.request_type,
    b.budgeting_status,
    CASE
        WHEN b.budgeting_status = 'Orçamento Aprovado' AND t.dt_service_appointment IS NULL THEN "Aguardando agendamento"
        WHEN b.budgeting_status = 'Orçamento Aprovado' AND t.dt_repair_completion IS NULL THEN "Em andamento"
        WHEN b.budgeting_status = 'Orçamento Aprovado' AND t.dt_service_appointment IS NOT NULL THEN "Execução concluída"
        ELSE NULL
    END AS execution_status,
    CASE
        WHEN t.repair_front = 'reparos_ongoing_novo'
            AND t.group_name = 'Prestadores Parceiros [REP] [POS] [BACK]'
            THEN 'reparos_ongoing'
        ELSE NULL
    END AS repair_form,
    t.ldt_opening,
    t.ldt_budget_submission,
    t.ldt_visit_scheduling,
    t.ldt_start_visit,
    t.ldt_technical_visit,
    t.ldt_budget_receipt,
    t.ldt_sent_to_cx,
    t.ldt_cx_return_with_approval,
    t.ldt_start_service_scheduling,
    t.ldt_service_scheduling,
    t.ldt_start_execution,
    t.ldt_execution_repair,
    t.ldt_execution,
    t.frt,
    CASE
        WHEN t.ldt_budget_submission-COALESCE(SUM(se.days_off),0) <=1 THEN True
        ELSE False
    END AS is_sla_budget_sent,
    CASE
        WHEN t.ldt_budget_receipt-COALESCE(SUM(sc.days_off),0) <=4 THEN True
        ELSE False
    END AS is_sla_budgeting,
    CASE
        WHEN t.ldt_execution-COALESCE(SUM(sx.days_off),0) <=15 THEN True
        ELSE False
    END AS is_sla_execution,
    t.dt_budget_submission_to_cx,
    t.dt_cx_disapproval_returned,
    t.dt_cx_approval_communication_for_ps,
    t.dt_budget_request_submitted,
    t.dt_budget_submission_by_ps,
    t.dt_repair_completion,
    t.dt_service_started,
    t.dt_cx_created,
    t.dt_created
FROM
    tickets t
LEFT JOIN
    sla_budget_sent se
        ON se.id_ticket = t.id_ticket
LEFT JOIN
    sla_budgeting sc
        ON sc.id_ticket = t.id_ticket
LEFT JOIN
    sla_execution sx
        ON sx.id_ticket = t.id_ticket
LEFT JOIN
    budgeting b
        ON b.id_ticket_referential = t.id_ticket_referential
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,29,30,31,32,33,34,35,36,37