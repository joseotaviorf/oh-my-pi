SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_provision

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_revenue_share

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.reverse_accounts_700005_700008_700009_700010_700011

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_revenue_accounting

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.reverse_accounts_420003_420019_420020_420025_611012

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_invoice

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.rental_guarantee_invoice

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_invoice_unified

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_write_off

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.reverse_accounts_513020

UNION ALL

SELECT
    id_accounting_process AS sk_accounting_process,
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
    sap_amount AS accounting_balance,
    is_completeness_compliance AS is_completeness,
    is_correctness_compliance AS is_correctness,
    is_temporality_compliance AS is_temporality,
    is_compliance,
    'straw' AS type,
    CAST(NULL AS STRING) AS accounting_process_status,
    CAST(NULL AS STRING) AS error_description,
    accrual_year_month,
    dt_source_trigger,
    dt_sap_reference,
    dt_sap_created,
    COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
    NOW() AS ts_load
FROM
    datalake_sap_accounting_process.kill_queue_reservation_issuance

UNION ALL

SELECT
    CONCAT('BANK-QA-FR-',id_finance_entity) AS sk_accounting_process,
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
    sap_amount AS accounting_balance,
    is_completeness_compliance AS is_completeness,
    is_correctness_compliance AS is_correctness,
    is_temporality_compliance AS is_temporality,
    is_compliance,
    'straw' AS type,
    CAST(NULL AS STRING) AS accounting_process_status,
    CAST(NULL AS STRING) AS error_description,
    accrual_year_month,
    dt_billing AS dt_source_trigger,
    dt_sap_reference,
    dt_sap_created,
    COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
    NOW() AS ts_load
FROM
    datalake_sap_accounting_process.for_rent_bank_settlement

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.retsuko_provision_reverse

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.reverse_accounts_420001_420002_420004

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.monopoly_invoices

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_transactional

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_transactional_third_parties

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
    datalake_sap_accounting_process.retsuko_third_parties

UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.monopoly_revenue_share

  UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.monopoly_provision

  UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.kill_queue_reverse

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.retsuko_invoice_unified_reverse

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.monopoly_invoices_reverse

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.monopoly_revenue_share_reverse
  
      UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.monopoly_provision_reverse

      UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.retsuko_transactional_reverse

      UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM 
  datalake_sap_accounting_process.retsuko_third_parties_reverse

      UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
  datalake_sap_accounting_process.retsuko_transactional_third_parties_reverse

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM
  datalake_sap_accounting_process.rental_guarantee_invoice_reverse

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
  datalake_sap_accounting_process.retsuko_postponement

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM
  datalake_sap_accounting_process.retsuko_postponement_reverse

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
  datalake_sap_accounting_process.retsuko_broker_commission

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM
  datalake_sap_accounting_process.retsuko_broker_commission_reverse

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  dt_filter_end,
  NOW() AS ts_load
FROM
  datalake_sap_accounting_process.retsuko_postponed_brokerage

    UNION ALL

SELECT
  id_accounting_process AS sk_accounting_process,
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
  sap_amount AS accounting_balance,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  'reverse straw' AS type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  COALESCE(dt_sap_reference, dt_source_trigger) AS dt_filter,
  CAST(NULL AS DATE) AS dt_filter_end,
  NOW() AS ts_load
FROM
  datalake_sap_accounting_process.retsuko_postponed_brokerage_reverse
