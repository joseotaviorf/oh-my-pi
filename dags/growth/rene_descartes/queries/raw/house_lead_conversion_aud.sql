SELECT 
	t.id,
	t.created_at,
	t.updated_at,
	t.house_lead_id,
	t.property_id,
	t.rev,
	t.revtype,
	t.revend,
	DATE(TO_TIMESTAMP(revtstmp/1000)) AS dt
FROM 
	house_lead_conversion_aud AS t
LEFT JOIN 
	revinfo AS r
		ON t.rev = r.rev
WHERE
	DATE(TO_TIMESTAMP(revtstmp/1000)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')