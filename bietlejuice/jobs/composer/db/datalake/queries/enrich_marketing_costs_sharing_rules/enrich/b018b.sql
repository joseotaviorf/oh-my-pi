--Branding cost share rule group 3 (https://docs.google.com/spreadsheets/d/11ExDZsnQ1IwiqgSy-13bVV5LGNET-ajUBmNoUryQtZE)
SELECT DISTINCT
	adt.id_date,
	'{id_rule}' AS id_rule,
	rgn.city_group,
	CASE
		WHEN rgn.city_group='Brasília' THEN 0.4850
		WHEN rgn.city_group='Goiânia' THEN 0.2280
        WHEN rgn.city_group='Curitiba' THEN 0.2870
		ELSE 0
	END AS share,
	'branding' AS funnel_side
FROM
	datalake_quintoandar.aux_date AS adt
INNER JOIN
	datalake_region.region AS rgn
		ON ad.date BETWEEN '2021-05-01' AND CURRENT_DATE
		AND rgn.city_group IN (
			'Brasília',
			'Goiânia',
			'Curitiba'
		)