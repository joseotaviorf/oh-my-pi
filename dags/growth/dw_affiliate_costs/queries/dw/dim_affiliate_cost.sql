SELECT
    id_rh_accounting_entry::BIGINT AS sk_rh_accounting_entry,
    id_payee::BIGINT AS sk_payee,
    LEFT(city_group::STRING,255) AS city_group,
    LEFT(description::STRING,255) AS description,
    LEFT(source_bill_item::STRING,255) AS source_bill_item,
    LEFT(commission_type::STRING,255) AS commission_type,
    LEFT(cost_center_code::STRING,255) AS cost_center_code,
    LEFT(mkt_origin::STRING,255) AS mkt_origin,
    now() as ts_load
FROM
    datalake_robin_hood.affiliate_costs