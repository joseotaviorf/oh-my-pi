WITH ticket_initial AS (
    SELECT
        rtm.id_ticket AS id_ticket_initial,
        CASE
            WHEN rtm.id_ticket_follow_up IS NULL THEN rtm.id_ticket
            ELSE rtm.id_ticket_follow_up
        END AS id_ticket_follow_up,
        rtm.id_ticket_referential,
        rtm.dt_created AS dt_initial_created
    FROM
        datalake_repair_services.repair_tickets_metrics rtm
    WHERE
        rtm.request_type = 'inicial_'
)
SELECT
    rtm.id_ticket_cx,
    ti.id_ticket_follow_up AS id_ticket,
    ti.id_ticket_initial,
    rtm.id_ticket_referential,
    rtm.id_contract,
    rtm.id_provider,
    rtm.id_zendesk_provider,
    rtm.budgeting_status,
    rtm.execution_status,
    rtm.repair_form,
    rtm.ldt_opening,
    rtm.ldt_budget_submission,
    rtm.ldt_visit_scheduling,
    rtm.ldt_start_visit,
    rtm.ldt_technical_visit,
    rtm.ldt_budget_receipt,
    rtm.ldt_sent_to_cx,
    rtm.ldt_cx_return_with_approval,
    rtm.ldt_start_service_scheduling,
    rtm.ldt_service_scheduling,
    rtm.ldt_start_execution,
    rtm.ldt_execution_repair,
    rtm.ldt_execution,
    rtm.frt,
    rtm.is_sla_budget_sent,
    rtm.is_sla_budgeting,
    rtm.is_sla_execution,
    rtm.dt_budget_submission_to_cx,
    rtm.dt_cx_disapproval_returned,
    rtm.dt_cx_approval_communication_for_ps,
    rtm.dt_budget_request_submitted,
    rtm.dt_budget_submission_by_ps,
    rtm.dt_repair_completion,
    rtm.dt_service_started,
    rtm.dt_cx_created,
    ti.dt_initial_created,
    rtm.dt_created
FROM
    ticket_initial ti
LEFT JOIN
    datalake_repair_services.repair_tickets_metrics rtm
        ON rtm.id_ticket = ti.id_ticket_follow_up