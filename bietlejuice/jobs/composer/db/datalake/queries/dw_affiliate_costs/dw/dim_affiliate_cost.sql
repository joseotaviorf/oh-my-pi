SELECT
    id_rh_accounting_entry AS sk_rh_accounting_entry,
    city_group,
    description,
    source_bill_item,
    commission_type,
    cost_center_code,
    mkt_origin,
    now() as ts_load
FROM
    datalake_robin_hood.affiliate_costs