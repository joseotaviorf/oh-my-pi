SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='RMSP' THEN 0.41
		WHEN rgn.city_group='Rio de Janeiro' THEN 0.20
		WHEN rgn.city_group='Belo Horizonte' THEN 0.08
		WHEN rgn.city_group='Porto Alegre' THEN 0.05
		WHEN rgn.city_group='Brasília' THEN 0.11
		WHEN rgn.city_group='Curitiba' THEN 0.06
		WHEN rgn.city_group='Florianópolis' THEN 0.01
		WHEN rgn.city_group='Campinas' THEN 0.04
		WHEN rgn.city_group='Santos' THEN 0.02
		WHEN rgn.city_group='Sorocaba' THEN 0.01
		WHEN rgn.city_group='Uberlândia' THEN 0.01
		ELSE 0
	END AS share,
	'social' AS funnel_side
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON adt.date BETWEEN '2022-01-01' AND CURRENT_DATE
		AND rgn.city_group IN (
			'RMSP',
			'Rio de Janeiro',
			'Belo Horizonte',
			'Porto Alegre',
			'Brasília',
			'Curitiba',
			'Florianópolis',
			'Campinas',
			'Santos',
			'Sorocaba',
			'Uberlândia'
		)