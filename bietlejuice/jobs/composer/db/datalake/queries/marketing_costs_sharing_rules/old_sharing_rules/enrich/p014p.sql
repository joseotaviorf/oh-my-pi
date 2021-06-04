WITH
ciq_results AS (
	SELECT
	    TO_CHAR(ts_created, 'YYYYMMDD') as sk_date,
	    DATE_TRUNC('WEEK', ts_created) as week_start,
	    dr.city_group,
	    COUNT(DISTINCT p.id) cnt_id
	FROM
	    datalake_ebdb_clean_prod.partner p
	    JOIN dim_region dr
	        ON p.city = dr.city_name
	WHERE
	    p.type = 'AUTONOMOUS_AGENT'
	    AND NULLIF(city_group,'') IS NOT NULL
	GROUP BY 1,2,3
),
dim_distinct as (
	SELECT
	    dd.sk_date,
		dd.week_start,
		dr.city_group
	FROM
		dim_date dd
		JOIN dim_region dr
			ON dd.date BETWEEN DATE('2021-02-15') AND CURRENT_DATE
	GROUP BY 1,2,3
),
aux AS ( --todas as combinações possíveis
	SELECT
		ddt.week_start,
		ddt.city_group,
        SUM(ciq.cnt_id) cnt_id
	FROM
		dim_distinct ddt
	LEFT JOIN ciq_results ciq
		ON ddt.week_start = ciq.week_start
		AND ddt.city_group = ciq.city_group
	GROUP BY 1,2
),
temp AS ( --Calculo do share por semana
	SELECT
		week_start,
		city_group,
		(
			sum(cnt_id) OVER (PARTITION BY week_start,city_group)
			/
			sum(cnt_id) OVER (PARTITION BY week_start)::float
		) AS current_share
	FROM
        aux
),
share AS (--pegando o share da ultima semana
	SELECT
		*,
		LAG(current_share, 1) OVER (PARTITION BY city_group ORDER BY week_start) AS share
	FROM
		temp
)
SELECT
	d.sk_date AS id_date,
	d.city_group,
	COALESCE(s.share, 0) AS share
FROM
	dim_distinct d
JOIN share s
	ON d.week_start = s.week_start
	AND d.city_group = s.city_group
WHERE
    d.week_start > DATE('2021-02-15')
GROUP BY 1,2,3