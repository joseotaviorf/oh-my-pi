SELECT
    rt.id_ticket AS sk_ticket,
    rt.budget_analyst AS responsible_budget,
    rt.responsible_execution,
    rt.payment_format,
    rt.reason_budget_delay,
    rt.reason_execution_delay,
    rt.request_type,
    rt.repair_type,
    rt.internal_evaluation,
    rt.occurrences,
    rt.additional_repair,
    rt.is_budget_visit_required,
    rt.is_service_guarantee,
    rt.dt_created
FROM
    datalake_repair_services.repair_tickets rt
WHERE
    repair_front IS NOT NULL