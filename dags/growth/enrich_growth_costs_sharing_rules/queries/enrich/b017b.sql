--Branding cost share rule group 2 (https://docs.google.com/spreadsheets/d/11ExDZsnQ1IwiqgSy-13bVV5LGNET-ajUBmNoUryQtZE)
SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='RMSP' THEN 0.6155
		WHEN rgn.city_group='Rio de Janeiro' THEN 0.3129
        WHEN rgn.city_group='Porto Alegre' THEN 0.0716
		ELSE 0
	END AS share,
	'branding' AS funnel_side,
	CAST(NULL AS STRING) AS business_context
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON adt.date BETWEEN '2021-05-01' AND CURRENT_DATE
		AND rgn.city_group IN (
			'RMSP',
			'Rio de Janeiro',
			'Porto Alegre'
		)