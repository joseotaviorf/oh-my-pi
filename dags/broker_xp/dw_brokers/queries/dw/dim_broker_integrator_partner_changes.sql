WITH integrator_partner_changes AS (
  SELECT
    bth.sk_company_product AS sk_broker_product,
    GET_JSON_OBJECT(bth.value, '$.integratorPartnerUUId') AS uuid_integrator_partner,
    bth.ts_transaction,
    LAG(GET_JSON_OBJECT(bth.value, '$.integratorPartnerUUId')) OVER (
      PARTITION BY bth.sk_company_product
      ORDER BY bth.ts_transaction
    ) AS prev_uuid_integrator_partner
  FROM
    core_brokers.broker_products_history AS bth
  WHERE
    bth.event_name = 'ev_product_settings'
),
filtered_changes AS (
  SELECT
    tc.sk_broker_product,
    tc.uuid_integrator_partner,
    ROW_NUMBER() OVER (PARTITION BY tc.sk_broker_product ORDER BY tc.ts_transaction) AS version,
    tc.ts_transaction
  FROM
    integrator_partner_changes AS tc
  WHERE
    tc.uuid_integrator_partner IS NOT NULL
    AND (
      tc.uuid_integrator_partner != tc.prev_uuid_integrator_partner
      OR tc.prev_uuid_integrator_partner IS NULL
    )
)
SELECT
  CONCAT(fc.sk_broker_product, fc.version) AS sk_broker_integrator_partner_change,
  bp.sk_broker AS sk_broker,
  bp.sk_broker_product,
  fc.uuid_integrator_partner,
  c.company_name AS integrator_partner,
  fc.version,
  LEAD(fc.ts_transaction) OVER (PARTITION BY fc.sk_broker_product ORDER BY fc.ts_transaction) IS NULL AS is_current,
  TRUE AS has_3p_access_control,
  fc.ts_transaction AS ts_start,
  LEAD(fc.ts_transaction) OVER (PARTITION BY fc.sk_broker_product ORDER BY fc.ts_transaction) AS ts_end,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(fc.ts_transaction) AS year,
  MONTH(fc.ts_transaction) AS month,
  DAY(fc.ts_transaction) AS day
FROM
  filtered_changes AS fc
JOIN
  core_brokers.brokers_product AS bp
    ON fc.sk_broker_product = bp.sk_broker_product
LEFT JOIN
  datalake_company_clean.company AS c
    ON fc.uuid_integrator_partner = c.uuid_company