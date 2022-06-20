SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='RMSP' THEN 0.6
		WHEN rgn.city_group='Rio de Janeiro' THEN 0.4
		ELSE 0
	END AS share,
	'social' AS funnel_side
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON adt.date BETWEEN '2010-01-01' AND CURRENT_DATE
		AND rgn.city_group IN (
			'RMSP',
			'Rio de Janeiro'
		)