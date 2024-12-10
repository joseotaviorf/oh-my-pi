SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='Florianópolis' THEN 0.2740
		WHEN rgn.city_group='Sorocaba' THEN 0.3672
		WHEN rgn.city_group='Uberlândia' THEN 0.3588
		ELSE 0
	END AS share,
	'branding' AS funnel_side,
	CAST(NULL AS STRING) AS business_context
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON adt.date BETWEEN '2022-01-01' AND CURRENT_DATE
		AND rgn.city_group IN (
			'Florianópolis',
			'Sorocaba',
			'Uberlândia'
		)