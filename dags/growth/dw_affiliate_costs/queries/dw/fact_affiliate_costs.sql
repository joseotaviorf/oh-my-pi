SELECT
    id_rh_accounting_entry AS sk_rh_accounting_entry,
    id_payee as sk_payee,
    dt_transaction AS sk_date,
    id_external AS sk_user,
    cost,
    now() as ts_load
FROM
    datalake_robin_hood.affiliate_costs
