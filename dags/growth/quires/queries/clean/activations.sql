SELECT
  id,
  installer,
  installerName AS installer_name,
  plate,
  property,
  transactionType AS transaction_type,
  url,
  utmCampaign AS utm_campaign,
  utmMedium AS utm_medium,
  utmSource AS utm_source,
  CAST(createdAt AS TIMESTAMP) AS ts_created,
  year,
  month,
  day
FROM
  datalake_quires_raw.activations
WHERE
  DATE(createdAt) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')