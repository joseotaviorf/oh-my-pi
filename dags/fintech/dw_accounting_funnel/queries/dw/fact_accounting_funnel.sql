SELECT
  id_accounting_process AS sk_accounting_funnel,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  business_unit,
  source_name,
  accounting_type,
  account_number,
  accounting_name,
  source_amount,
  sap_amount,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_provision

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_funnel,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  business_unit,
  source_name,
  accounting_type,
  account_number,
  accounting_name,
  source_amount,
  sap_amount,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_revenue_share

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_funnel,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  business_unit,
  source_name,
  accounting_type,
  account_number,
  accounting_name,
  source_amount,
  sap_amount,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_revenue_accounting

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_funnel,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  business_unit,
  source_name,
  accounting_type,
  account_number,
  accounting_name,
  source_amount,
  sap_amount,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_invoice

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_funnel,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  version,
  business_unit,
  source_name,
  accounting_type,
  account_number,
  accounting_name,
  source_amount,
  sap_amount,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_invoice_unified

UNION ALL

SELECT
    id_accounting_process AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    'kill-queue' AS version,
    business_unit,
    source_name,
    accounting_type,
    account_number,
    accounting_name,
    source_amount,
    sap_amount,
    is_completeness_compliance AS is_completeness,
    is_correctness_compliance AS is_correctness,
    is_temporality_compliance AS is_temporality,
    is_compliance,
    CAST(NULL AS STRING) AS accounting_process_status,
    CAST(NULL AS STRING) AS error_description,
    accrual_year_month,
    dt_source_trigger,
    dt_sap_reference,
    dt_sap_created,
    NOW() AS ts_load
FROM
    datalake_sap_accounting_process.kill_queue_reservation_issuance

UNION ALL

SELECT
    CONCAT('BANK-QC-',id_finance_entity) AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    id_external_payment AS id_finance_entity_entry,
    'quintocred' AS version,
    'quintocred' AS business_unit,
    billing_source AS source_name,
    'bank' AS accounting_type,
    sap_account_number AS account_number,
    'quintocred' AS accounting_name,
    bank_amount AS source_amount,
    sap_amount,
    is_completeness_compliance AS is_completeness,
    is_correctness_compliance AS is_correctness,
    is_temporality_compliance AS is_temporality,
    is_compliance,
    CAST(NULL AS STRING) AS accounting_process_status,
    CAST(NULL AS STRING) AS error_description,
    CAST(NULL AS INTEGER) AS accrual_year_month,
    dt_bank_paid AS dt_source_trigger,
    dt_sap_reference,
    dt_sap_created,
    NOW() AS ts_load
FROM
    datalake_sap_accounting_process.quintocred_bank_settlement

UNION ALL

SELECT
    CONCAT('BANK-QA-FR-',id_finance_entity) AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    company_use AS id_finance_entity_entry,
    version,
    'for rent' AS business_unit,
    billing_source AS source_name,
    'bank' AS accounting_type,
    sap_account_number AS account_number,
    'for rent' AS accounting_name,
    billing_amount AS source_amount,
    sap_amount,
    is_completeness_compliance AS is_completeness,
    is_correctness_compliance AS is_correctness,
    is_temporality_compliance AS is_temporality,
    is_compliance,
    accrual_year_month,
    CAST(NULL AS STRING) AS accounting_process_status,
    CAST(NULL AS STRING) AS error_description,
    dt_billing AS dt_source_trigger,
    dt_sap_reference,
    dt_sap_created,
    NOW() AS ts_load
FROM
    datalake_sap_accounting_process.for_rent_bank_settlement
