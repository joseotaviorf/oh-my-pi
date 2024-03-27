SELECT 
  id_retsuko_invoice_issuance AS sk_invoice_issuance,
  id_business_entity,
  id_finance_entity,
  source_name,
  revenue_name,
  accrual_year_month,
  source_amount,
  sap_amount,
  is_compliance, 
  dt_created
FROM 
  datalake_accounting_funnel.retsuko_invoice_issuance