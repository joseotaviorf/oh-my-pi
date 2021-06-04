--Branding cost share rule group 1 (https://docs.google.com/spreadsheets/d/11ExDZsnQ1IwiqgSy-13bVV5LGNET-ajUBmNoUryQtZE)
SELECT
	dd.sk_date AS id_date,
	dr.city_group,
	CASE
		WHEN dr.city_group='Campinas' THEN 0.2863
		WHEN dr.city_group='Florianópolis' THEN 0.116
        	WHEN dr.city_group='Belo Horizonte' THEN 0.5977
		ELSE 0
	END AS share
FROM
	dim_date dd
	JOIN dim_region dr
		ON dd.date BETWEEN '2021-05-01' AND CURRENT_DATE
		AND dr.city_group IN ('Campinas','Florianópolis','Belo Horizonte')
GROUP BY 1,2,3
