SELECT 
  id_retsuko_provision_creation AS sk_provision_creation,
  id_business_entity,
  id_finance_entity,
  source_name,
  revenue_name,
  accrual_year_month,
  source_provision_amount,
  sap_provision_amount,
  source_reversion_amount,
  sap_reversion_amount,
  is_provision_compliance,
  is_reversion_compliance,
  dt_created
FROM 
  datalake_accounting_funnel.retsuko_provision_creation