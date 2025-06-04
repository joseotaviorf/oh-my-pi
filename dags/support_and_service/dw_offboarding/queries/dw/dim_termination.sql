WITH terminations AS (
    SELECT
        id_termination,
        cancellation_info,
        category,
        requested_by,
        status,
        feedback,
        reason,
        rescheduling_history,
        workflow_current_step,
        fee_negotiation_status,
        fee_payment_option,
        checklist_item,
        decline_person,
        NOW() AS ts_load,
        year,
        month,
        day
    FROM
        datalake_terminator.termination
    WHERE
        DATE(ts_termination_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
mediations AS (
    SELECT
        id_termination,
        id_ticket,
        squad,
        has_mediation_ticket,
        has_ac_repairs,
        is_ticket_opened_via_terminator,
        dt_inspection
    FROM
        datalake_offboarding.mediations
    WHERE
        DATE(ts_termination_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    t.id_termination AS sk_termination,
    m.id_ticket AS sk_mediation_ticket,
    t.team,
    t.cancellation_info,
    t.category,
    t.requested_by,
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
    IF(((m.has_ac_repairs = TRUE) AND ((m.has_mediation_ticket = TRUE AND m.squad <> 'both_agreed') OR (m.has_mediation_ticket = FALSE AND m.squad IS NULL))), TRUE, FALSE) AS has_mediation,
    m.has_mediation_ticket,
    m.has_ac_repairs,
    m.is_ticket_opened_via_terminator,
    m.dt_inspection,
    NOW() AS ts_load,
    t.year,
    t.month,
    t.day
FROM
    terminations AS t
LEFT JOIN
    mediations AS m
        ON m.id_termination = t.id_termination
