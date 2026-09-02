WITH source_broker_commission AS (
  SELECT DISTINCT
    CAST(e.id_external AS STRING) AS id_finance_entity_entry
  FROM
    datalake_retsuko.entry e
  INNER JOIN
    datalake_retsuko_clean.account af
      ON af.id = e.id_from_account
  INNER JOIN
    datalake_retsuko_clean.account atc
      ON atc.id = e.id_to_account
  LEFT JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = e.id_contract
  WHERE
    e.bill_item IN (
      'entry.bill-item/brokerage-adm-partner',
      'entry.bill-item/brokerage-adm-partner-postponed',
      'entry.bill-item/brokerage-fee-tax-ir-adm-partner',
      'entry.bill-item/brokerage-partner-select',
      'entry.bill-item/brokerage-partner-select-postponed'
    )
    AND (
      (af.type = 'landlord' AND atc.type = 'contract')
      OR (af.type = 'contract' AND atc.type = 'landlord')
    )
    AND ct.country_code = 'BR'
    AND DATE(e.ts_created) >= '2025-01-01'
),

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
    LEFT JOIN
      datalake_sap_gateway_clean.webhook_log w
        ON s.idoc = w.idoc
    WHERE
      s.erp_solution IN ('S4')
      AND s.type = 'LCM'
      AND s.status NOT IN ('ignore', 'ignored')
  )
  WHERE
    rn = 1
),

sap_ledger AS (
  SELECT
    CAST(id_finance_entity_entry AS STRING) AS id_finance_entity_entry,
    MAX(id_business_entity) AS id_business_entity,
    MAX(id_finance_entity) AS id_finance_entity,
    MAX(accrual_year_month) AS accrual_year_month,
    MAX(hash) AS hash,
    SUM(debit_credit) AS debit_credit,
    MAX(DATE(dt_created)) AS dt_sap_created,
    MAX(DATE(dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    account_number = '211408'
    AND dt_reference >= DATE('2025-01-01')
    AND id_finance_entity_entry IS NOT NULL
  GROUP BY 1
),

source_dispatch_hash AS (
  SELECT DISTINCT
    sg.hash
  FROM
    source_broker_commission sb
  INNER JOIN
    datalake_retsuko_clean.sap_entity se
      ON CAST(se.id_finance_entity AS STRING) = sb.id_finance_entity_entry
      AND se.event = 'new-accounting-entries'
  INNER JOIN
    sap_gateway sg
      ON sg.id_feature = CAST(se.id_sap_gateway_feature AS STRING)
  WHERE
    sg.hash IS NOT NULL
),

sap_ledger_unkeyed AS (
  SELECT
    CAST(l.id_transaction AS STRING) AS id_transaction,
    MAX(l.created_by) AS created_by,
    MAX(l.id_business_entity) AS id_business_entity,
    MAX(l.id_finance_entity) AS id_finance_entity,
    MAX(l.accrual_year_month) AS accrual_year_month,
    MAX(l.hash) AS hash,
    SUM(l.debit_credit) AS debit_credit,
    MAX(DATE(l.dt_created)) AS dt_sap_created,
    MAX(DATE(l.dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger l
  LEFT JOIN
    source_dispatch_hash sdh
      ON sdh.hash = l.hash
  WHERE
    l.account_number = '211408'
    AND l.dt_reference >= DATE('2025-01-01')
    AND l.id_finance_entity_entry IS NULL
    AND sdh.hash IS NULL
  GROUP BY 1
)

SELECT
  ('RE-RTSK-BRKC'||'-'||sl.id_finance_entity_entry) AS id_accounting_process,
  sl.id_business_entity,
  sl.id_finance_entity,
  sl.id_finance_entity_entry,
  CAST(NULL AS STRING) AS version,
  'for rent' AS business_unit,
  'S4' AS source_name,
  'broker commission' AS accounting_type,
  '211408' AS account_number,
  'broker commission to transfer' AS accounting_name,
  CAST(NULL AS DECIMAL(12,2)) AS source_amount,
  CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
  FALSE AS is_completeness,
  FALSE AS is_correctness,
  FALSE AS is_temporality,
  FALSE AS is_compliance,
  'reverse straw failure' AS accounting_process_status,
  CASE
    WHEN sg.hash IS NULL THEN 'manual transaction'
    WHEN sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL THEN COALESCE(sg.type, '') || ' - ' || COALESCE(sg.webhook_error, sg.sync_sap_job_status, '')
    ELSE 'source not dispatched by retsuko broker commission'
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
  source_broker_commission sb
    ON sb.id_finance_entity_entry = sl.id_finance_entity_entry
WHERE
  sb.id_finance_entity_entry IS NULL

UNION ALL

SELECT
  ('RE-RTSK-BRKC-MAN'||'-'||m.id_transaction) AS id_accounting_process,
  m.id_business_entity,
  m.id_finance_entity,
  CAST(NULL AS STRING) AS id_finance_entity_entry,
  CAST(NULL AS STRING) AS version,
  'for rent' AS business_unit,
  'S4' AS source_name,
  'broker commission' AS accounting_type,
  '211408' AS account_number,
  'broker commission to transfer' AS accounting_name,
  CAST(NULL AS DECIMAL(12,2)) AS source_amount,
  CAST(m.debit_credit AS DECIMAL(12,2)) AS sap_amount,
  FALSE AS is_completeness,
  FALSE AS is_correctness,
  FALSE AS is_temporality,
  FALSE AS is_compliance,
  'reverse straw failure' AS accounting_process_status,
  CASE
    WHEN m.hash IS NULL THEN CONCAT('posting without gateway hash - ', COALESCE(m.created_by, 'unknown'))
    ELSE CONCAT('source dispatched without finance entity entry - ', COALESCE(m.created_by, 'unknown'))
  END AS error_description,
  m.accrual_year_month,
  CAST(NULL AS DATE) AS dt_source_trigger,
  m.dt_sap_reference,
  m.dt_sap_created
FROM
  sap_ledger_unkeyed m
