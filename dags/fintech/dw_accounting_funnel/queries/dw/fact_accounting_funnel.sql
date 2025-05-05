SELECT
    id_retsuko_provision_creation AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    source_name,
    'provision' AS accounting_type,
    revenue_name AS accounting_name,
    accrual_year_month,
    status,
    source_amount,
    sap_amount,
    account_number,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    is_compliance,
    dt_source_trigger,
    dt_sap_created,
    dt_sap_reference,
    NOW() AS ts_load
FROM 
    datalake_accounting_funnel.retsuko_provision_creation

UNION ALL

SELECT
    id_retsuko_reversion_creation AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    source_name,
    'reversion' AS accounting_type,
    revenue_name AS accounting_name,
    accrual_year_month,
    status,
    source_amount,
    sap_amount,
    account_number,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    is_compliance,
    dt_source_trigger,
    dt_sap_created,
    dt_sap_reference,
    NOW() AS ts_load
FROM 
    datalake_accounting_funnel.retsuko_reversion_creation

UNION ALL

SELECT
    id_retsuko_revenue_accounting AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    source_name,
    'revenue accounting' AS accounting_type,
    revenue_name AS accounting_name,
    accrual_year_month,
    status,
    source_amount,
    sap_amount,
    account_number,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    is_compliance,
    dt_source_trigger,
    dt_sap_created,
    dt_sap_reference,
    NOW() AS ts_load
FROM 
    datalake_accounting_funnel.retsuko_revenue_accounting

UNION ALL

SELECT
    id_retsuko_invoice_issuance AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    source_name,
    'invoice' AS accounting_type,
    revenue_name AS accounting_name,
    accrual_year_month,
    status,
    source_amount,
    sap_amount,
    account_number,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    is_compliance,
    dt_source_trigger,
    dt_sap_created,
    dt_sap_reference,
    NOW() AS ts_load
FROM 
    datalake_accounting_funnel.retsuko_invoice_issuance

UNION ALL 

SELECT
    id_kill_queue_invoice_issuance AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    'kill-queue' AS version,
    source_name,
    'invoice' AS accounting_type,
    revenue_name AS accounting_name,
    accrual_year_month,
    status,
    source_amount,
    sap_amount,
    account_number,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    is_compliance,
    dt_source_trigger,
    dt_sap_created,
    dt_sap_reference,
    NOW() AS ts_load
FROM 
    datalake_accounting_funnel.kill_queue_invoice_issuance

UNION ALL 

SELECT
    CONCAT('BANK-QC-',id_finance_entity) AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    id_external_payment AS id_finance_entity_entry,
    'quintocred' AS version,
    billing_source AS source_name,
    'bank' AS accounting_type,
    'quintocred' AS accounting_name,
    CAST(NULL AS INTEGER) AS accrual_year_month,
    CAST(NULL AS STRING) AS status,
    bank_amount AS source_amount,
    sap_amount,
    sap_account_number AS account_number,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    is_compliance,
    dt_bank_paid AS dt_source_trigger,
    dt_sap_created,
    dt_sap_reference,
    NOW() AS ts_load    
FROM 
    quintocred_bank_settlement

UNION ALL 

SELECT
    CONCAT('BANK-QA-FR-',id_finance_entity) AS sk_accounting_funnel,
    id_business_entity,
    id_finance_entity,
    company_use AS id_finance_entity_entry,
    version,
    billing_source AS source_name,
    'bank' AS accounting_type,
    'for rent' AS accounting_name,
    accrual_year_month,
    CAST(NULL AS STRING) AS status,
    billing_amount AS source_amount,
    sap_amount,
    sap_account_number AS account_number,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    is_compliance,
    dt_billing AS dt_source_trigger,
    dt_sap_created,
    dt_sap_reference,
    NOW() AS ts_load    
FROM 
    for_rent_bank_settlement