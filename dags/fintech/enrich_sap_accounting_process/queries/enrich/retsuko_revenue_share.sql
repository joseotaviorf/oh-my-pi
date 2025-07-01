WITH

retsuko AS(
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-estate-agent') THEN '700006'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') AND LOWER(e.description) LIKE '%consultor imobiliário%' THEN '700007'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN '700009'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-partner-select') THEN '700010'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') THEN '700011'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-estate-agent') THEN 'brokerage agent'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') AND LOWER(e.description) LIKE '%consultor imobiliário%' THEN 'brokerage CIQ'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN 'adm fee partner'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-partner-select') THEN 'brokerage select'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') THEN 'B2B brokerage partner'
    END AS accounting_name,
    i.accrual_year_month,
    DATE(e.ts_created) AS dt_source_trigger,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN CAST(-ABS(amount) AS DECIMAL(12,2))
      ELSE CAST(amount AS DECIMAL(12,2))
    END AS source_amount
    FROM
      datalake_retsuko.entry  e
    INNER JOIN
      datalake_retsuko_clean.account AS af
        ON e.id_from_account = af.id
    INNER JOIN
      datalake_retsuko_clean.account AS at
        ON e.id_to_account = at.id
    LEFT JOIN
      datalake_retsuko.invoice i
        ON e.id_invoice = i.id
    LEFT JOIN
      datalake_retsuko.invoice_info ii
        ON ii.id_invoice = i.id_external
    LEFT JOIN
      datalake_retsuko_clean.contract ct
        ON ct.id = e.id_contract
    WHERE
        TRUE
        AND e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select', 'entry.bill-item/brokerage-estate-agent', 'entry.bill-item/adm-fee-adm-partner')
        AND ct.country_code = 'BR'
        AND DATE(e.ts_created) >= '2024-01-01'
        AND af.type IN ('contract', 'tenant','landlord')
        AND at.type IN ('contract', 'tenant','landlord')
        AND (i.is_write_off = FALSE OR i.is_write_off IS NULL)

),

retsuko_aggregate AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select', 'entry.bill-item/brokerage-estate-agent') THEN '700005'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN '700008'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select', 'entry.bill-item/brokerage-estate-agent') THEN 'brokerage partners'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN 'B2B adm partner'
    END AS accounting_name,
    i.accrual_year_month,
    DATE(e.ts_created) AS dt_source_trigger,
    CAST(amount AS DECIMAL(12,2)) AS source_amount
  FROM
    datalake_retsuko.entry  e
  INNER JOIN
    datalake_retsuko_clean.account AS af
      ON e.id_from_account = af.id
  INNER JOIN
    datalake_retsuko_clean.account AS at
      ON e.id_to_account = at.id
  LEFT JOIN
    datalake_retsuko.invoice i
      ON e.id_invoice = i.id
  LEFT JOIN
    datalake_retsuko.invoice_info ii
      ON ii.id_invoice = i.id_external
  LEFT JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = e.id_contract
  WHERE
    TRUE
    AND e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select', 'entry.bill-item/brokerage-estate-agent', 'entry.bill-item/adm-fee-adm-partner')
    AND ct.country_code = 'BR'
    AND DATE(e.ts_created) >= '2024-01-01'
    AND af.type IN ('contract', 'tenant','landlord')
    AND at.type IN ('contract', 'tenant','landlord')
    AND (i.is_write_off = FALSE OR i.is_write_off IS NULL)
),

retsuko_final AS (
  SELECT * FROM retsuko
  UNION ALL
  SELECT * FROM retsuko_aggregate
),

sap_entity AS(
  SELECT
    id_finance_entity,
    id_sap_gateway_feature,
    version,
    event,
    status,
    failed_status,
    failed_reason
  FROM
    datalake_retsuko_clean.sap_entity
  WHERE
    id_finance_entity IS NOT NULL
    AND event IN ('new-accounting-entries', 'payment-accounting-entries')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
),

sap_gateway AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
    s.status as sync_sap_job_status,
    w.status as sap_send_status,
    w.webhook_status as sap_processed_status,
    w.errors AS webhook_error
  FROM
    datalake_sap_gateway_clean.feature f
  LEFT JOIN
    datalake_sap_gateway_clean.sync_sap_job s
      ON f.id_feature = s.id_feature
  LEFT JOIN
    datalake_sap_gateway_clean.webhook_log w
      ON s.idoc = w.idoc
  WHERE
    erp_solution IN ('S4')
    AND type = 'LCM'
    AND s.status NOT IN ('ignore', 'ignored')
    AND DATE(f.ts_created) >= DATE('2024-01-01')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, f.id_feature ORDER BY f.ts_updated) = 1
),

sap_ledger AS (
  SELECT
    id_finance_entity,
    id_finance_entity_entry,
    hash,
    account_number,
    SUM(debit_credit) AS debit_credit,
    DATE(dt_created) AS dt_sap_created,
    DATE(dt_reference) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    dt_reference >= DATE('2024-01-01')
    AND account_number IN ('700005','700006', '700007', '700008', '700009', '700010', '700011')
  GROUP BY 1, 2, 3, 4, 6, 7
),

errors_base AS (
  SELECT
    r.id_business_entity,
    r.id_finance_entity,
    r.id_finance_entity_entry,
    se.version,
    r.source_name,
    r.account_number,
    r.accounting_name,
    r.accrual_year_month,
    MIN(CASE
      WHEN sl.hash IS NOT NULL THEN 'success'
      WHEN sl.hash IS NULL AND (se.id_finance_entity IS NULL OR se.status = 'failed' OR se.failed_reason IS NOT NULL) THEN 'source failure'
      WHEN sl.hash IS NULL AND (sg.id_feature IS NULL OR sg.sync_sap_job_status = 'error' OR sg.webhook_error IS NOT NULL) THEN 'gateway failure'
      ELSE 'unknown failure'
    END) AS accounting_process_status,
    MIN(CASE
      WHEN sl.hash IS NULL AND se.id_finance_entity IS NULL THEN 'source not found'
      WHEN sl.hash IS NULL AND se.status = 'failed' THEN se.failed_reason
      WHEN sl.hash IS NULL AND sg.id_feature IS NULL THEN 'gateway not found'
      WHEN sl.hash IS NULL AND sg.sync_sap_job_status = 'error' THEN sg.webhook_error
      WHEN sl.hash IS NULL AND se.id_finance_entity IS NOT NULL AND sg.id_feature IS NOT NULL THEN 'sap not found'
      ELSE NULL
    END) AS error_description,
    MIN(IF(sl.hash IS NULL, FALSE, TRUE)) AS is_completeness,
    CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
    CAST(SUM(sl.debit_credit) AS DECIMAL(12,2)) AS sap_amount,
    MAX(r.dt_source_trigger) AS dt_source_trigger,
    MAX(sl.dt_sap_created) AS dt_sap_created,
    MAX(sl.dt_sap_reference) AS dt_sap_reference
  FROM
    retsuko_final r
  LEFT JOIN
    sap_entity se
      ON r.id_finance_entity_entry = se.id_finance_entity
  LEFT JOIN
    sap_gateway sg
      ON se.id_sap_gateway_feature = sg.id_feature
  LEFT JOIN
    sap_ledger sl
      ON r.account_number = sl.account_number
      AND sl.hash = sg.hash
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 12
),

assertions_base AS (
  SELECT
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    source_name,
    account_number,
    accounting_name,
    source_amount,
    sap_amount,
    is_completeness,
    accounting_process_status,
    error_description,
    accrual_year_month,
    dt_source_trigger,
    dt_sap_reference,
    dt_sap_created,
    IF((ABS(source_amount) - ABS(sap_amount)) >= 0.05 OR (ABS(source_amount) - ABS(sap_amount)) <= -0.05 OR sap_amount IS NULL, FALSE, TRUE) AS is_correctness,
    IF(dt_sap_reference BETWEEN dt_source_trigger AND DATE_ADD(dt_source_trigger, 3), TRUE, FALSE) AS is_temporality
  FROM errors_base
)

SELECT
  ('FR-RRS'||'-'||IF(id_finance_entity_entry IS NOT NULL, id_finance_entity_entry, id_finance_entity)||'-'|| accounting_number) AS id_accounting_process,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  'for rent' AS business_unit,
  source_name,
  'revenue share' AS accounting_type,
  account_number,
  accounting_name,
  source_amount,
  sap_amount,
  is_completeness,
  is_correctness,
  is_temporality,
  IF(is_completeness IS TRUE AND is_correctness IS TRUE AND is_temporality IS TRUE, TRUE, FALSE) AS is_compliance,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created
FROM assertions_base
