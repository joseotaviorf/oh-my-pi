SELECT 
	t.*,
	DATE(TO_TIMESTAMP(revtstmp/1000)) AS dt
FROM 
	house_lead_aud AS t
LEFT JOIN 
	revinfo AS r
ON t.rev = r.rev
WHERE
	DATE(TO_TIMESTAMP(revtstmp/1000)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')