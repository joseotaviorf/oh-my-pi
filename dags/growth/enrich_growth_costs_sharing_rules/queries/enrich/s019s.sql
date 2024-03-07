SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='RMSP' THEN 0.55009
		WHEN rgn.city_group='Rio de Janeiro' THEN 0.18684
		WHEN rgn.city_group='Campinas' THEN 0.05055
		WHEN rgn.city_group='Belo Horizonte' THEN 0.05221
		WHEN rgn.city_group='Brasília' THEN 0.0295
		WHEN rgn.city_group='Goiânia' THEN 0.05761
		WHEN rgn.city_group='Porto Alegre' THEN 0.01899
		WHEN rgn.city_group='Curitiba' THEN 0.02388
		WHEN rgn.city_group='Florianópolis' THEN 0.01395
		WHEN rgn.city_group='Recife' THEN 0.00546
		WHEN rgn.city_group='Salvador' THEN 0.00546
		WHEN rgn.city_group='Santos' THEN 0.00546
		ELSE 0
	END AS share,
	'branding' AS funnel_side,
	CAST(NULL AS STRING) AS business_context
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON adt.date BETWEEN '2010-01-01' AND CURRENT_DATE
		AND rgn.city_group IN (
			'RMSP',
			'Rio de Janeiro',
			'Campinas',
			'Belo Horizonte',
			'Brasília',
			'Goiânia',
			'Porto Alegre',
			'Curitiba',
			'Florianópolis',
			'Recife',
			'Salvador',
			'Santos'
		)