SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='Goiânia' THEN 0.78125
		WHEN rgn.city_group='Vitória' THEN 0.0625
		WHEN rgn.city_group='São José dos Campos' THEN 0.03125
		WHEN rgn.city_group='São José do Rio Preto' THEN 0.03125
		WHEN rgn.city_group='Ribeirão Preto' THEN 0.03125
		WHEN rgn.city_group='Mogi das Cruzes' THEN 0.03125
		WHEN rgn.city_group='RMSP' THEN 0.03125
		ELSE 0
	END AS share,
	'social' AS funnel_side
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON adt.date BETWEEN '2021-01-01' AND CURRENT_DATE
		AND rgn.city_group IN (
			'Goiânia',
			'Vitória',
			'São José dos Campos',
			'São José do Rio Preto',
			'Ribeirão Preto',
			'Mogi das Cruzes',
			'RMSP'
		)