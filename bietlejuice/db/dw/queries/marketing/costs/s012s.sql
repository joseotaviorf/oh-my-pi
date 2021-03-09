--Social cost share rule 60% RMSP, 40% RJ
SELECT
	dd.sk_date,
	dr.city_group,
	CASE
		WHEN dr.city_group='RMSP' THEN 0.6
		WHEN dr.city_group='Rio de Janeiro' THEN 0.4
		ELSE 0
	END AS share
FROM
	dim_date dd
	JOIN dim_region dr
		ON dd.date BETWEEN '2010-01-01' AND CURRENT_DATE
		AND dr.city_group IN ('RMSP','Rio de Janeiro')
