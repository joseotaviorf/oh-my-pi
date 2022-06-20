SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='Campinas' THEN 0.53912
		WHEN rgn.city_group='Curitiba' THEN 0.25468
		WHEN rgn.city_group='Florianópolis' THEN 0.14879
		WHEN rgn.city_group='Santos' THEN 0.03608
		WHEN rgn.city_group='Sorocaba' THEN 0.01066
		WHEN rgn.city_group='Uberlândia' THEN 0.01066
		ELSE 0
	END AS share,
	'social' AS funnel_side
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON adt.date BETWEEN '2021-01-01' AND CURRENT_DATE
		AND rgn.city_group IN (
			'Campinas',
			'Curitiba',
			'Florianópolis',
			'Santos',
			'Sorocaba',
			'Uberlândia'
		)