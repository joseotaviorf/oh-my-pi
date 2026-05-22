SELECT
    CAST(id_rh_accounting_entry AS BIGINT) AS sk_rh_accounting_entry,
    CAST(id_payee AS BIGINT) AS sk_payee,
    LEFT(CAST(city_group AS STRING), 255) AS city_group,
    LEFT(CAST(description AS STRING), 255) AS description,
    LEFT(CAST(source_bill_item AS STRING), 255) AS source_bill_item,
    LEFT(CAST(commission_type AS STRING), 255) AS commission_type,
    LEFT(CAST(cost_center_code AS STRING), 255) AS cost_center_code,
    LEFT(CAST(mkt_origin AS STRING), 255) AS mkt_origin,
    NOW() AS ts_load
FROM
    datalake_robin_hood.affiliate_costs
