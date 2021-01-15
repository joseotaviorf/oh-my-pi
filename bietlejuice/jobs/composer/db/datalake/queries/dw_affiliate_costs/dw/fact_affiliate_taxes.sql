SELECT
  id AS sk_tax,
  id_payee as sk_payee,
  due_amount,
  accounting_year_month as dt_accounting_year_month,
  now() as ts_load
FROM datalake_robin_hood_clean.tax
WHERE due_amount IS NOT NULL