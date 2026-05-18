WITH status_changes AS (
  SELECT
    ch.sk_broker,
    CONCAT(ch.sk_broker, 27) AS sk_broker_product,
    ch.broker_status,
    'Rede Sale' AS product_name,
    'Hubspot' AS status_origin,
    ch.ts_updated,
    LAG(ch.broker_status) OVER (PARTITION BY ch.sk_broker ORDER BY ch.ts_updated) AS prev_status
  FROM
    datalake_brokers.hubspot_brokers_history AS ch
  WHERE
    DATE(ch.ts_updated) <= '2026-01-31'
      AND ch.broker_status IS NOT NULL

  UNION ALL

  SELECT
    bph.id_company AS sk_broker,
    bph.sk_company_product AS sk_broker_product,
    bph.value AS broker_status,
    bp.product_name,
    'Company' AS status_origin,
    bph.ts_transaction AS ts_updated,
    LAG(bph.value) OVER (PARTITION BY bph.id_company, bph.id_product ORDER BY bph.ts_transaction) AS prev_status
  FROM
    core_brokers.broker_products_history AS bph
    LEFT JOIN core_brokers.brokers_product AS bp ON bph.sk_company_product = bp.sk_broker_product
  WHERE
    bph.ts_transaction >= '2026-02-01'
      AND bph.event_name = 'ev_status'
      AND bph.value IS NOT NULL
),
status_cohorts AS (
  SELECT
    sc.sk_broker,
    sc.sk_broker_product,
    sc.broker_status,
    sc.product_name,
    sc.status_origin,
    sc.ts_updated AS ts_start,
    LEAD(sc.ts_updated) OVER (PARTITION BY sc.sk_broker, sc.product_name ORDER BY sc.ts_updated ASC) AS ts_end
  FROM
    status_changes AS sc
  WHERE
    sc.broker_status != sc.prev_status
    OR sc.prev_status IS NULL
)
SELECT
  CONCAT(sc.sk_broker_product, DATE_FORMAT(sc.ts_start, 'yyyyMMddHHmmss')) AS id_status_change,
  sc.sk_broker,
  sc.broker_status,
  sc.product_name,
  sc.status_origin,
  sc.ts_end IS NULL AS is_current,
  TRUE AS has_3p_access_control,
  sc.ts_start,
  sc.ts_end,
  CURRENT_TIMESTAMP() AS ts_load
FROM
  status_cohorts AS sc