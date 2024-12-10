SELECT
	t.*,
	DATE(TO_TIMESTAMP(revtstmp/1000)) AS dt,
  CAST(EXTRACT(YEAR FROM DATE(TO_TIMESTAMP(revtstmp/1000))) AS INT) AS year,
  CAST(EXTRACT(MONTH FROM DATE(TO_TIMESTAMP(revtstmp/1000))) AS INT) AS month,
  CAST(EXTRACT(DAY FROM DATE(TO_TIMESTAMP(revtstmp/1000))) AS INT) AS day
FROM
	lead_rejection_aud AS t
LEFT JOIN
	revinfo AS r
    ON t.rev = r.rev
WHERE
  DATE(TO_TIMESTAMP(revtstmp/1000)) >= DATE(DATE('{execution_date}') - INTERVAL '6 day')
  AND DATE(TO_TIMESTAMP(revtstmp/1000)) < DATE(DATE('{execution_date}') + INTERVAL '1 day')
