--Branding cost share rule group 3 (https://docs.google.com/spreadsheets/d/11ExDZsnQ1IwiqgSy-13bVV5LGNET-ajUBmNoUryQtZE)
SELECT
	dd.sk_date AS id_date,
	dr.city_group,
	CASE
		WHEN dr.city_group='Brasília' THEN 0.4850
		WHEN dr.city_group='Goiânia' THEN 0.2280
        	WHEN dr.city_group='Curitiba' THEN 0.2870
		ELSE 0
	END AS share
FROM
	dim_date dd
	JOIN dim_region dr
		ON dd.date BETWEEN '2021-05-01' AND CURRENT_DATE
		AND dr.city_group IN ('Brasília','Goiânia','Curitiba')
GROUP BY 1,2,3
