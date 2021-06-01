--Branding cost share rule group 2 (https://docs.google.com/spreadsheets/d/11ExDZsnQ1IwiqgSy-13bVV5LGNET-ajUBmNoUryQtZE)
SELECT
	dd.sk_date,
	dr.city_group,
	CASE
		WHEN dr.city_group='RMSP' THEN 0.6155
		WHEN dr.city_group='Rio de Janeiro' THEN 0.3129
        	WHEN dr.city_group='Porto Alegre' THEN 0.0716
		ELSE 0
	END AS share
FROM
	dim_date dd
	JOIN dim_region dr
		ON dd.date BETWEEN '2021-05-01' AND CURRENT_DATE
		AND dr.city_group IN ('RMSP','Rio de Janeiro','Porto Alegre')
GROUP BY 1,2,3
