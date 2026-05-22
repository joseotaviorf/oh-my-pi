SELECT
    CAST(id_rh_accounting_entry AS BIGINT) AS sk_rh_accounting_entry,
    CAST(id_payee AS BIGINT) AS sk_payee,
    CAST(dt_transaction AS BIGINT) AS sk_date,
    CAST(id_external AS BIGINT) AS sk_user,
    CAST(cost AS DECIMAL(20, 2)),
    NOW() AS ts_load
FROM
    datalake_robin_hood.affiliate_costs
