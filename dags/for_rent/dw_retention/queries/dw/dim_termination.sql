SELECT
    id_termination AS sk_termination,
    repair_cost,
    status,
    ts_created,
    NOW() AS ts_load
FROM
    datalake_offboarding.contract_termination