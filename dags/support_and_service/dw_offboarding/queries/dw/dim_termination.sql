SELECT
    id_termination AS sk_termination,
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
