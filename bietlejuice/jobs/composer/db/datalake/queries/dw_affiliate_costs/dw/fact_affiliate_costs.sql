SELECT
    id_rh_accounting_entry AS sk_rh_accounting_entry,
    dt_transaction AS sk_date,
    id_external AS sk_user,
    cost,
    tax
FROM
    datalake_robin_hood.affiliate_costs
