WITH terminations AS (
    SELECT
        id_termination,
        team,
        cancellation_info,
        category,
        requested_by,
        source,
        status,
        feedback,
        reason,
        rescheduling_history,
        workflow_current_step,
        fee_negotiation_status,
        fee_payment_option,
        checklist_item,
        decline_person,
        task_type,
        responsible_off_manager_email,
        repair_resolution,
        has_landlord_comment,
        has_repair_by_tenant_needed,
        total_tentant_repair_ac > 0 AS has_ac_repairs,
        year,
        month,
        day
    FROM
        transformation_terminator_test_curated.termination
    WHERE
        DATE(ts_termination_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    t.id_termination AS sk_termination,
    m.id_mediation_ticket AS sk_mediation_ticket,
    t.team,
    t.cancellation_info,
    t.category,
    t.requested_by,
    t.source,
    t.status,
    t.feedback,
    t.reason,
    t.rescheduling_history,
    m.squad AS mediation_squad,
    t.workflow_current_step,
    t.fee_negotiation_status,
    t.fee_payment_option,
    t.checklist_item,
    t.decline_person,
    t.task_type,
    t.responsible_off_manager_email,
    t.repair_resolution,
    m.has_mediation_ticket,
    t.has_ac_repairs,
    m.is_ticket_opened_via_terminator,
    t.has_landlord_comment,
    t.has_repair_by_tenant_needed,
    m.dt_inspection,
    NOW() AS ts_load,
    t.year,
    t.month,
    t.day
FROM
    terminations AS t
LEFT JOIN
    transformation_offboarding_test_curated.mediations AS m
        ON m.id_termination = t.id_termination
