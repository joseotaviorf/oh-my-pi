SELECT
  *,
  DATE(updated_at) AS dt,
  CAST(EXTRACT(YEAR FROM updated_at) AS INT) AS year,
  CAST(EXTRACT(MONTH FROM updated_at) AS INT) AS month,
  CAST(EXTRACT(DAY FROM updated_at) AS INT) AS day
FROM
  lead_rejection
WHERE
  updated_at >= DATE(DATE('{execution_date}') - INTERVAL '6 day')
  AND updated_at < DATE(DATE('{execution_date}') + INTERVAL '1 day')
