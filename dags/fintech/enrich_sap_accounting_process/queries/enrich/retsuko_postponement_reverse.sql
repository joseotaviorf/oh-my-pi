-- Reverse straw for account 211407 (postponed invoice - PP). It walks the same route as
-- retsuko_postponement, but backwards: it anchors on the SAP ledger and keeps the postings the
-- forward straw cannot see, because the forward straw starts from the Retsuko entry.
--
-- Two populations end up here. Postings with no postponement entry at all are genuine reverse
-- straw failures. Postings whose entry exists but sits on a tenant-owned invoice are the mirror
-- of the 'account divergence' bucket in the forward straw: SAP booked them as PP while the
-- invoice ownership proxy reads them as IQ, so they are labelled instead of blamed on the source.
WITH source_postponement AS (
  SELECT DISTINCT
    CAST(e.id_external AS STRING) AS id_finance_entity_entry,
    ia.type AS invoice_owner_type
  FROM
    datalake_retsuko.entry e
  INNER JOIN
    datalake_retsuko.invoice i
      ON CAST(e.id_invoice AS STRING) = CAST(i.id AS STRING)
  INNER JOIN
    datalake_retsuko_clean.account ia
      ON ia.id = i.id_account
  INNER JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = i.id_contract
  WHERE
    e.bill_item = 'entry.bill-item/postponement'
    AND ct.country_code = 'BR'
    AND DATE(e.ts_created) >= '2025-01-01'
),

-- Same gateway leg as the forward straw, used only to tell a posting that never reached the
-- gateway (manual entry) from one that reached it and still has no source dispatch.
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

source_dispatch_hash AS (
  SELECT DISTINCT
    sg.hash
  FROM
    source_postponement sp
  INNER JOIN
    datalake_retsuko_clean.sap_entity se
      ON CAST(se.id_finance_entity AS STRING) = sp.id_finance_entity_entry
      AND se.event = 'new-accounting-entries'
  INNER JOIN
    sap_gateway sg
      ON sg.id_feature = CAST(se.id_sap_gateway_feature AS STRING)
  WHERE
    sp.invoice_owner_type = 'landlord'
    AND sg.hash IS NOT NULL
),

-- Anchor of the reverse straw. No accounting_rule filter on purpose: the whole account is in
-- scope so that any rule that starts posting to 211407 shows up here instead of disappearing.
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
    account_number = '211407'
    AND dt_reference >= DATE('2025-01-01')
    AND id_finance_entity_entry IS NOT NULL
  GROUP BY 1
),

-- Postings booked into the account with no finance entity entry. They carry no key the entry
-- level join could ever match, so they are grouped by transaction and reported separately
-- instead of being dropped for lack of a join key. Two kinds live here: batch postings that
-- reached the gateway but carry no entry id, and adjustments typed straight into SAP by a user,
-- which have neither hash nor finance entity.
sap_ledger_manual AS (
  SELECT
    CAST(l.id_transaction AS STRING) AS id_transaction,
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
    l.account_number = '211407'
    AND l.dt_reference >= DATE('2025-01-01')
    AND l.id_finance_entity_entry IS NULL
    AND sdh.hash IS NULL
  GROUP BY 1
)

SELECT
  ('RE-RTSK-PSTP'||'-'||sl.id_finance_entity_entry) AS id_accounting_process,
  sl.id_business_entity,
  sl.id_finance_entity,
  sl.id_finance_entity_entry,
  CAST(NULL AS STRING) AS version,
  'for rent' AS business_unit,
  'S4' AS source_name,
  'postponement' AS accounting_type,
  '211407' AS account_number,
  'postponed invoice PP' AS accounting_name,
  CAST(NULL AS DECIMAL(12,2)) AS source_amount,
  CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
  FALSE AS is_completeness,
  FALSE AS is_correctness,
  FALSE AS is_temporality,
  FALSE AS is_compliance,
  CASE
    WHEN sp.invoice_owner_type = 'tenant' THEN 'account divergence'
    ELSE 'reverse straw failure'
  END AS accounting_process_status,
  CASE
    WHEN sp.invoice_owner_type = 'tenant' THEN 'dispatched as IQ postponed invoice - accounted in 211407'
    WHEN sg.hash IS NULL THEN 'manual transaction'
    WHEN sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL THEN COALESCE(sg.type, '') || ' - ' || COALESCE(sg.webhook_error, sg.sync_sap_job_status, '')
    ELSE 'source not dispatched by retsuko postponement'
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
  source_postponement sp
    ON sp.id_finance_entity_entry = sl.id_finance_entity_entry
WHERE
  COALESCE(sp.invoice_owner_type, 'none') <> 'landlord'

UNION ALL

SELECT
  ('RE-RTSK-PSTP-MAN'||'-'||m.id_transaction) AS id_accounting_process,
  m.id_business_entity,
  m.id_finance_entity,
  CAST(NULL AS STRING) AS id_finance_entity_entry,
  CAST(NULL AS STRING) AS version,
  'for rent' AS business_unit,
  'S4' AS source_name,
  'postponement' AS accounting_type,
  '211407' AS account_number,
  'postponed invoice PP' AS accounting_name,
  CAST(NULL AS DECIMAL(12,2)) AS source_amount,
  CAST(m.debit_credit AS DECIMAL(12,2)) AS sap_amount,
  FALSE AS is_completeness,
  FALSE AS is_correctness,
  FALSE AS is_temporality,
  FALSE AS is_compliance,
  'reverse straw failure' AS accounting_process_status,
  CASE
    WHEN m.hash IS NULL THEN 'manual transaction'
    ELSE 'source dispatched without finance entity entry'
  END AS error_description,
  m.accrual_year_month,
  CAST(NULL AS DATE) AS dt_source_trigger,
  m.dt_sap_reference,
  m.dt_sap_created
FROM
  sap_ledger_manual m
