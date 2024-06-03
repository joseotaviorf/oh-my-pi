SELECT
    id_termination AS sk_termination,
    cancellation_info,
    category,
    requested_by,
    status,
    feedback,
    rescheduling_history
    workflow_current_step,
    fee_negotiation_status,
    fee_payment_option,
    checklist_item,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_terminator.termination
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
