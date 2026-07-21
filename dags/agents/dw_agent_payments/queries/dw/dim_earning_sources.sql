SELECT
    es.id AS sk_earning_source,
    IF(es.external_domain_type = 'RENT_CONTRACT', es.id_external_domain, NULL) AS sk_contract,
    IF(es.external_domain_type = 'SALES_FLOW', es.id_external_domain, NULL) AS sk_sales_flow,
    cart.id AS sk_cart,
    es.uuid_external_cart AS uuid_cart,
    es.external_domain_type AS domain_type,
    es.currency,
    es.status,
    es.failure_reason,
    es.base_amount,
    es.revenue_share_total_amount,
    es.dt_competence,
    DATE(es.ts_created) AS dt_partition,
    es.ts_occurred,
    es.ts_created,
    es.ts_updated,
    NOW() AS ts_load,
    YEAR(es.ts_created) AS year,
    MONTH(es.ts_created) AS month,
    DAY(es.ts_created) AS day
FROM
    datalake_big_agent_clean.earning_sources AS es
LEFT JOIN
    datalake_cart_system_clean.cart AS cart
        ON es.uuid_external_cart = cart.uuid_cart
WHERE
    DATE(es.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')