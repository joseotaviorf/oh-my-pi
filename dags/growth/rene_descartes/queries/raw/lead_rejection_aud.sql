SELECT
	t.*,
	DATE(TO_TIMESTAMP(revtstmp/1000)) AS dt,
  CAST(EXTRACT(YEAR FROM TO_TIMESTAMP(revtstmp/1000)) AS INT) AS year,
  CAST(EXTRACT(MONTH FROM TO_TIMESTAMP(revtstmp/1000)) AS INT) AS month,
  CAST(EXTRACT(DAY FROM TO_TIMESTAMP(revtstmp/1000)) AS INT) AS day
FROM
	lead_rejection_aud AS t
LEFT JOIN
	revinfo AS r
    ON t.rev = r.rev
WHERE
  TO_TIMESTAMP(revtstmp/1000) >= '{execution_date}' - INTERVAL '6 day'
  AND TO_TIMESTAMP(revtstmp/1000) < '{execution_date}' + INTERVAL '1 day'
