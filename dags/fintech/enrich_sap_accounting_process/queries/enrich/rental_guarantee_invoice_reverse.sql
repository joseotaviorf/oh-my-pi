-- Reverse straw for the Rental Guarantee share of account 420010. It walks the same route as
-- rental_guarantee_invoice, but backwards: it anchors on the SAP ledger and keeps only the
-- postings that never had a revenue recognition dispatch on the rental-guarantee side, which
-- the forward straw cannot see because it starts from the dispatch.
WITH rental_guarantee AS (
  SELECT DISTINCT
    CAST(id_feature AS STRING) AS id_feature
  FROM
    datalake_rental_guarantee_clean.sap
  WHERE
    `trigger` IN (
      'PIX_REVENUE_RECOGNITION',
      'CREDIT_CARD_REVENUE_RECOGNITION',
      'STANDALONE_REVENUE_RECOGNITION')
    AND DATE(dt_event_date) >= DATE('2025-01-01')
    AND id_feature IS NOT NULL
),

-- Same gateway leg as the forward straw, so both directions agree on which feature owns each
-- hash. The join to feature scopes the leg to rental-guarantee and keeps the Seu Barriga
-- postings on the same account out of this table.
sap_gateway AS (
  SELECT
    id_feature,
    hash,
    type,
    sync_sap_job_status,
    webhook_error
  FROM (
    SELECT
      CAST(s.id_feature AS STRING) AS id_feature,
      s.hash,
      s.type,
      s.status AS sync_sap_job_status,
      w.errors AS webhook_error,
      ROW_NUMBER() OVER (PARTITION BY s.id_feature ORDER BY s.ts_updated DESC) AS rn
    FROM
      datalake_sap_gateway_clean.sync_sap_job s
    JOIN
      datalake_sap_gateway_clean.feature f
        ON f.id_feature = s.id_feature
        AND f.source = 'rental-guarantee'
    LEFT JOIN
      datalake_sap_gateway_clean.webhook_log w
        ON s.idoc = w.idoc
    WHERE
      s.erp_solution IN ('S4')
      AND s.type = 'NF'
      AND s.status NOT IN ('ignore', 'ignored')
      AND DATE(s.ts_created) >= DATE('2025-01-01')
  )
  WHERE
    rn = 1
),

-- Account 420010 also carries postings issued through the legacy B1 ERP during the 2024
-- migration. They never travelled through the S4 gateway, so they are outside the straw by
-- design and are removed here instead of being reported as reverse straw failures.
legacy_b1 AS (
  SELECT DISTINCT
    hash
  FROM
    datalake_sap_gateway_clean.sync_sap_job
  WHERE
    erp_solution = 'B1'
    AND hash IS NOT NULL
    AND year >= 2023
),

-- Anchor of the reverse straw. The scope matches the forward straw line by line so that the
-- two tables partition the same ledger population: accounting_rule separates rental-guarantee
-- from Seu Barriga, and hash is the only key the ledger shares with the gateway.
sap_ledger AS (
  SELECT
    hash,
    MAX(id_business_entity) AS id_business_entity,
    MAX(id_finance_entity) AS id_finance_entity,
    MAX(id_finance_entity_entry) AS id_finance_entity_entry,
    MAX(accrual_year_month) AS accrual_year_month,
    SUM(debit_credit) AS debit_credit,
    MAX(DATE(dt_created)) AS dt_sap_created,
    MAX(DATE(dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    dt_reference >= DATE('2025-01-01')
    AND account_number = '420010'
    AND accounting_rule IN ('pro-guarantor-nf', 'standalone-nf')
    AND hash IS NOT NULL
  GROUP BY 1
),

-- Account 420010 also carries postings that belong to neither source: no accounting_rule, no
-- gateway hash and no business entity. They are adjustments posted straight into SAP by people or
-- by batch workflows. Because both forward straws split the account by accounting_rule and join
-- the ledger by hash, this population was invisible in both directions, which is exactly what a
-- reverse straw exists to prevent. They are grouped by transaction, since there is no other key,
-- and carry a NULL accounting_name because they cannot be attributed to rental guarantee or to
-- Seu Barriga.
sap_ledger_unkeyed AS (
  SELECT
    CAST(id_transaction AS STRING) AS id_transaction,
    MAX(created_by) AS created_by,
    MAX(accrual_year_month) AS accrual_year_month,
    SUM(debit_credit) AS debit_credit,
    MAX(DATE(dt_created)) AS dt_sap_created,
    MAX(DATE(dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    dt_reference >= DATE('2025-01-01')
    AND account_number = '420010'
    AND accounting_rule IS NULL
    AND hash IS NULL
  GROUP BY 1
)

SELECT
  ('RE-RGRT-I'||'-'||sl.hash) AS id_accounting_process,
  sl.id_business_entity,
  sl.id_finance_entity,
  sl.id_finance_entity_entry,
  CAST(NULL AS STRING) AS version,
  'for rent' AS business_unit,
  'S4' AS source_name,
  'invoice' AS accounting_type,
  '420010' AS account_number,
  'rental guarantee' AS accounting_name,
  CAST(NULL AS DECIMAL(12,2)) AS source_amount,
  CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
  FALSE AS is_completeness,
  FALSE AS is_correctness,
  FALSE AS is_temporality,
  FALSE AS is_compliance,
  'reverse straw failure' AS accounting_process_status,
  CASE
    WHEN sg.hash IS NULL THEN 'transaction missing in sap gateway'
    WHEN sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL THEN COALESCE(sg.type, '') || ' - ' || COALESCE(sg.webhook_error, sg.sync_sap_job_status, '')
    ELSE 'source not dispatched by rental guarantee'
  END AS error_description,
  sl.accrual_year_month,
  CAST(NULL AS DATE) AS dt_source_trigger,
  sl.dt_sap_reference,
  sl.dt_sap_created
FROM
  sap_ledger sl
LEFT JOIN
  sap_gateway sg
    ON sg.hash = sl.hash
LEFT JOIN
  rental_guarantee r
    ON r.id_feature = sg.id_feature
LEFT JOIN
  legacy_b1 b1
    ON b1.hash = sl.hash
WHERE
  r.id_feature IS NULL
  AND b1.hash IS NULL

UNION ALL

SELECT
  ('RE-RGRT-I-NOHASH'||'-'||m.id_transaction) AS id_accounting_process,
  CAST(NULL AS STRING) AS id_business_entity,
  CAST(NULL AS STRING) AS id_finance_entity,
  CAST(NULL AS STRING) AS id_finance_entity_entry,
  CAST(NULL AS STRING) AS version,
  'for rent' AS business_unit,
  'S4' AS source_name,
  'invoice' AS accounting_type,
  '420010' AS account_number,
  CAST(NULL AS STRING) AS accounting_name,
  CAST(NULL AS DECIMAL(12,2)) AS source_amount,
  CAST(m.debit_credit AS DECIMAL(12,2)) AS sap_amount,
  FALSE AS is_completeness,
  FALSE AS is_correctness,
  FALSE AS is_temporality,
  FALSE AS is_compliance,
  'reverse straw failure' AS accounting_process_status,
  CONCAT('posting without gateway hash - ', COALESCE(m.created_by, 'unknown')) AS error_description,
  m.accrual_year_month,
  CAST(NULL AS DATE) AS dt_source_trigger,
  m.dt_sap_reference,
  m.dt_sap_created
FROM
  sap_ledger_unkeyed m
