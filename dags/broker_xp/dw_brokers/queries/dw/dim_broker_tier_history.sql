WITH tier_changes AS (
  SELECT
    bth.sk_company_product AS sk_broker_product,
    bth.value AS id_tier,
    bth.ts_transaction,
    LAG(bth.value) OVER (PARTITION BY bth.sk_company_product ORDER BY bth.ts_transaction) AS prev_id_tier
  FROM
    core_brokers.broker_tiers_history AS bth
  WHERE
    bth.event_name = 'ev_id_tier'
),
filtered_changes AS (
  SELECT
    tc.sk_broker_product,
    tc.id_tier,
    ROW_NUMBER() OVER (PARTITION BY tc.sk_broker_product ORDER BY tc.ts_transaction) AS version,
    tc.ts_transaction
  FROM
    tier_changes AS tc
  WHERE
    tc.id_tier IS NOT NULL
    AND (tc.id_tier != tc.prev_id_tier OR tc.prev_id_tier IS NULL)
)
SELECT
  CONCAT(fc.sk_broker_product, fc.version) AS sk_broker_tier_history,
  bp.sk_broker AS sk_broker,
  bp.sk_broker_product,
  fc.id_tier,
  t.tier_name,
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
  datalake_company_clean.tier AS t
    ON CAST(fc.id_tier AS BIGINT) = t.id