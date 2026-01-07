WITH

retsuko AS (
  SELECT DISTINCT
    ct.id_external AS id_business_entity,
    ct.landlord_legal_person AS contract_type,
    i.id_external AS id_finance_entity,
    e.id_external AS id_finance_entity_entry,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'physical' THEN '420002'
      WHEN e.bill_item = 'entry.bill-item/service-fee' THEN '420005'
    END AS account_number,
    CASE
      WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') THEN 'adm fee PF'
      WHEN e.bill_item = 'entry.bill-item/service-fee' THEN 'service fee'
    END AS accounting_name,
    CASE
      WHEN e.bill_item != 'entry.bill-item/service-fee' THEN e.accrual_year_month
      WHEN (ct.is_rental_paid_in_advance = true AND e.producer = 'onboarding-routine') THEN e.accrual_year_month
      WHEN (ct.is_rental_paid_in_advance = true AND e.producer = 'onboarding-routine-delayed') THEN e.accrual_year_month
      WHEN ct.is_rental_paid_in_advance = false THEN e.accrual_year_month
      ELSE e.accrual_year_month + 1
    END AS accrual_year_month,
    CASE
      WHEN e.bill_item != 'entry.bill-item/service-fee' THEN DATE_FORMAT(DATE_TRUNC('month', TO_DATE(CAST(e.accrual_year_month AS VARCHAR(10)), 'yyyyMM')) + interval '1' month - interval '1' day, 'yyyy-MM-dd')
      WHEN (ct.is_rental_paid_in_advance = true AND e.producer = 'onboarding-routine') THEN DATE_FORMAT(DATE_TRUNC('month', TO_DATE(CAST(e.accrual_year_month AS VARCHAR(10)), 'yyyyMM')) + interval '1' month - interval '1' day, 'yyyy-MM-dd')
      WHEN (ct.is_rental_paid_in_advance = true AND e.producer = 'onboarding-routine-delayed') THEN DATE_FORMAT(DATE_TRUNC('month', TO_DATE(CAST(e.accrual_year_month AS VARCHAR(10)), 'yyyyMM')) + interval '1' month - interval '1' day, 'yyyy-MM-dd')
      WHEN ct.is_rental_paid_in_advance = false THEN DATE_FORMAT(DATE_TRUNC('month', TO_DATE(CAST(e.accrual_year_month AS VARCHAR(10)), 'yyyyMM')) + interval '1' month - interval '1' day, 'yyyy-MM-dd')
      ELSE DATE_FORMAT(DATE_TRUNC('month', TO_DATE(CAST((e.accrual_year_month + 1) AS VARCHAR(10)), 'yyyyMM')) + interval '1' month - interval '1' day, 'yyyy-MM-dd')
    END AS dt_source_trigger,
    CAST(e.amount AS DECIMAL(12,2)) AS source_amount
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
    datalake_retsuko_clean.contract ct
      ON ct.id = e.id_contract
  WHERE
    e.description != 'Crédito - Parcelamento corretagem - QuintoAndar'
    AND e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin', 'entry.bill-item/service-fee')
    AND ct.country_code = 'BR'
    AND DATE(e.ts_created) >= DATE ('2025-01-01')
    AND af.type IN ('contract', 'tenant', 'landlord')
    AND at.type IN ('contract', 'tenant','landlord')
    AND i.status != 'canceled'
    AND NOT(ct.landlord_legal_person = 'juridical' AND e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin'))
),

sap_entity AS (
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
    AND event IN ('tenant-invoices-paid', 'nota-fiscal-items', 'new-accounting-entries')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
),

sap_gateway AS (
   SELECT
    i.id_feature,
    i.id_finance_entity,
    i.amount,
    CAST(ci.doc_entry AS INT) AS doc_entry,
    s.status as sync_sap_job_status
  --  w.status as sap_send_status,
  --  w.webhook_status as sap_processed_status,
  --  w.errors AS webhook_error
FROM
    datalake_sap_gateway_clean.invoice i
LEFT JOIN
  datalake_sap_gateway_clean.consolidated_invoice ci
    ON ci.id = i.id_consolidated
INNER JOIN
  datalake_sap_gateway_clean.sync_sap_job s
    ON i.id_feature = s.id_feature
--LEFT JOIN
--    datalake_sap_gateway_clean.webhook_log w
--      ON s.idoc = w.idoc
WHERE
    i.account_code in ('SRPN000001','SRPN000006')
    AND s.type IN ('NF', 'PN')
    AND s.status IN ('waiting-unified-invoice', 'done')
    AND s.erp_solution IN ('S4')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.id_finance_entity, i.id_feature ORDER BY s.ts_updated) = 1

--- obs.: o que está comentando será ativado quando o processo for automático
),

sap_ledger AS (
  SELECT
    id_finance_entity,
    account_number,
    id_external_payment,
    SUM(debit_credit) AS debit_credit,
    MAX(DATE(dt_created)) AS dt_sap_created,
    MAX(DATE(dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger
  WHERE
    dt_reference >= DATE('2024-01-01')
    AND account_number IN ('420002', '420005')
  GROUP BY 1, 2, 3
),

errors_base AS (
  SELECT
    r.id_business_entity,
    r.id_finance_entity,
    r.id_finance_entity_entry,
    sg.doc_entry AS version,
    r.source_name,
    r.account_number,
    r.accounting_name,
    r.accrual_year_month,
    MIN(CASE
      WHEN sl.id_external_payment IS NOT NULL THEN 'success'
      WHEN sl.id_external_payment IS NULL AND (se.id_finance_entity IS NULL OR se.status = 'failed' OR se.failed_reason IS NOT NULL) THEN 'source failure'
      WHEN sl.id_external_payment IS NULL AND (sg.id_feature IS NULL OR sg.sync_sap_job_status = 'error') THEN 'gateway failure'
      ELSE 'unknown failure'
    END) AS accounting_process_status,
    MIN(CASE
      WHEN sl.id_external_payment IS NULL AND se.id_finance_entity IS NULL THEN 'source not found'
      WHEN sl.id_external_payment IS NULL AND se.status = 'failed' THEN se.failed_reason
      WHEN sl.id_external_payment IS NULL AND sg.id_feature IS NULL THEN 'gateway not found'
      --WHEN sl.id_finance_entity IS NULL AND sg.sync_sap_job_status = 'error' THEN COALESCE(sg.type, '') || ' - ' || COALESCE(sg.webhook_error, '')
      WHEN sl.id_external_payment IS NULL AND se.id_finance_entity IS NOT NULL AND sg.id_feature IS NOT NULL THEN 'sap not found'
      ELSE NULL
    END) AS error_description,
    MIN(IF(sl.id_external_payment IS NULL, FALSE, TRUE)) AS is_completeness,
    CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
    MIN(CASE
      WHEN 
        sg.doc_entry IS NOT NULL AND sl.id_external_payment IS NOT NULL THEN CAST(sg.amount AS DECIMAL(12,2))
      WHEN 
        sl.debit_credit IS NOT NULL THEN CAST(sl.debit_credit AS DECIMAL(12,2))
      ELSE NULL
    END) AS sap_amount,
    MAX(r.dt_source_trigger) AS dt_source_trigger,
    MAX(sl.dt_sap_created) AS dt_sap_created,
    MAX(sl.dt_sap_reference) AS dt_sap_reference
  FROM
    retsuko r
  LEFT JOIN
    sap_entity se
      ON r.id_finance_entity_entry = se.id_finance_entity
  LEFT JOIN
    sap_gateway sg
      ON se.id_sap_gateway_feature = sg.id_feature
  LEFT JOIN
    sap_ledger sl
      ON sl.id_external_payment = sg.doc_entry
      OR ( r.account_number = sl.account_number AND r.id_finance_entity = sl.id_finance_entity)
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 12
),

assertions_base AS (
  SELECT
    ('FR-UI'||'-'||IF(id_finance_entity_entry IS NOT NULL, id_finance_entity_entry, id_finance_entity)||'-'|| COALESCE(account_number, '')) AS id_accounting_process,
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
  id_accounting_process||'-'||ROW_NUMBER() OVER (PARTITION BY id_accounting_process ORDER BY dt_sap_created) AS id_accounting_process,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  'for rent' AS business_unit,
  source_name,
  'unified invoice' AS accounting_type,
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
