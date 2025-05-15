CREATE OR REPLACE TABLE datalake_rental_management.condo_monitoring_eligibility_aud
PARTITIONED BY (year, month, day)
LOCATION "s3://5a-datalake-prod/enrich/rental_management/condo_monitoring_eligibility_aud/" AS
SELECT
  BIGINT(id) AS id,
  BIGINT(id_contract) AS id_contract,
  eligibility,
  ts_created,
  ts_updated,
  rev_type,
  YEAR(ts_updated) AS year,
  MONTH(ts_updated) AS month,
  DAY(ts_updated) AS day
FROM
  datalake_condominium_payments_clean.condo_monitoring_eligibility_aud
WHERE
  DATE(ts_updated) < "2025-05-15"
