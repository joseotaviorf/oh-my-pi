SELECT
    id_termination AS sk_termination,
    repair_cost,
    status,
    category,
    send_utility_bills_receipt,
    attachment_type_list,
    dt_ended_termination,
    ts_created,
    NOW() AS ts_load
FROM
    datalake_offboarding.contract_termination