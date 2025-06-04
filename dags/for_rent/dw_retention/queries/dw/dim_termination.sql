SELECT
    id_termination AS sk_termination,
    repair_cost,
    repair_resolution,
    status,
    category,
    send_utility_bills_receipt,
    attachment_type_list,
    requested_by,
    dt_ended_termination,
    dt_termination,
    ts_termination_finished,
    ts_created,
    NOW() AS ts_load
FROM
    datalake_offboarding.contract_termination
