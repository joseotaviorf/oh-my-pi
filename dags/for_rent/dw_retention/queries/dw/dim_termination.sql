SELECT
    id_termination AS sk_termination,
    repair_cost,
    NOW() AS ts_load
FROM
    datalake_offboarding.contract_termination