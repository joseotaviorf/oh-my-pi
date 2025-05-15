CREATE OR REPLACE TABLE datalake_rental_management.condo_monitoring_actions_aud
PARTITIONED BY (year, month, day)
LOCATION "s3://5a-datalake-prod/enrich/rental_management/condo_monitoring_actions_aud/" AS
SELECT
  BIGINT(id) AS id,
  BIGINT(id_contract) AS id_contract,
  BIGINT(id_action_main_user) AS id_action_main_user,
  action_type,
  action_main_user_email,
  action_system,
  invoice_user_name,
  invoice_user_document,
  invoice_issuer_name,
  invoice_issuer_document,
  ts_created,
  ts_updated,
  rev_type,
  YEAR(ts_updated) AS year,
  MONTH(ts_updated) AS month,
  DAY(ts_updated) AS day
FROM
  datalake_condominium_payments_clean.condo_monitoring_actions_aud
WHERE
  DATE(ts_updated) < "2025-05-15"
