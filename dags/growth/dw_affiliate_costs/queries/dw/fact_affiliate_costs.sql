SELECT
    id_rh_accounting_entry::BIGINT AS sk_rh_accounting_entry,
    id_payee::BIGINT AS sk_payee,
    dt_transaction::BIGINT AS sk_date,
    id_external::BIGINT AS sk_user,
    cost::DECIMAl(20,2),
    now() AS ts_load
FROM
    datalake_robin_hood.affiliate_costs