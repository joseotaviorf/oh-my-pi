-- Rateio arbitrário baseado em share de investimento para cidades estratégicas (São Paulo, Rio de Janeiro, Porto Alegre, Belo Horizonte e Brasília)

SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
        WHEN rgn.city_group='RMSP' THEN 0.47
        WHEN rgn.city_group='Rio de Janeiro' THEN 0.33
        WHEN rgn.city_group='Belo Horizonte' THEN 0.11
        WHEN rgn.city_group='Porto Alegre' THEN 0.04
		WHEN rgn.city_group='Brasília' THEN 0.05
		ELSE 0
	END AS share,
	'branding' AS funnel_side,
	CAST(NULL AS STRING) AS business_context
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON adt.date BETWEEN DATE('2022-01-01') AND CURRENT_DATE
		AND rgn.city_group IN (
            'RMSP',
			'Rio de Janeiro',
			'Belo Horizonte',
			'Porto Alegre',
            'Brasília'
		)