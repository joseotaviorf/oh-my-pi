CREATE OR REPLACE TABLE datalake_rental_management.invoice_aud
PARTITIONED BY (year, month, day)
LOCATION "s3://5a-datalake-prod/enrich/rental_management/invoice_aud/" AS
SELECT
  BIGINT(id) AS id,
  id_external,
  BIGINT(id_invoice_user) AS id_invoice_user,
  BIGINT(id_contract) AS id_contract,
  value,
  status,
  raw_data,
  dt_due,
  ts_created,
  ts_updated,
  rev_type,
  YEAR(ts_updated) AS year,
  MONTH(ts_updated) AS month,
  DAY(ts_updated) AS day
FROM
  datalake_condominium_payments_clean.invoice_aud
WHERE
  DATE(ts_updated) < "2025-05-15"
