SELECT
  id::BIGINT AS sk_tax,
  id_payee::BIGINT as sk_payee,
  due_amount::DECIMAL(20,2) AS due_amount,
  accounting_year_month::BIGINT AS dt_accounting_year_month,
  now() as ts_load
FROM datalake_robin_hood_clean.tax
WHERE due_amount IS NOT NULL