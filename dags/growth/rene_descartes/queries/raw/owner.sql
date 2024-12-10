SELECT
  *,
  DATE(updated_at) AS dt,
  CAST(EXTRACT(YEAR FROM DATE(updated_at)) AS INT) AS year,
  CAST(EXTRACT(MONTH FROM DATE(updated_at)) AS INT) AS month,
  CAST(EXTRACT(DAY FROM DATE(updated_at)) AS INT) AS day
FROM
  owner
WHERE
  DATE(updated_at) >= DATE(DATE('{execution_date}') - INTERVAL '6 day')
  AND DATE(updated_at) < DATE(DATE('{execution_date}') + INTERVAL '1 day')
