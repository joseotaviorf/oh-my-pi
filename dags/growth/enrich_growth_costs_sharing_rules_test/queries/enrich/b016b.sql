--Branding cost share rule group 1 (https://docs.google.com/spreadsheets/d/11ExDZsnQ1IwiqgSy-13bVV5LGNET-ajUBmNoUryQtZE)
SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='Campinas' THEN 0.2863
		WHEN rgn.city_group='Florianópolis' THEN 0.116
        WHEN rgn.city_group='Belo Horizonte' THEN 0.5977
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
			'Campinas',
			'Florianópolis',
			'Belo Horizonte'
		)