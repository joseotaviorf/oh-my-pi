WITH t_row_count AS ( --contagem de prospects
    SELECT
        dd.week_start,
        fhlf.mkt_origin,
        dr.city_group,
        COUNT(1) AS row_count
    FROM
        dw_public.fact_house_listing_flows AS fhlf
    JOIN datalake_region.region AS dr
        ON dr.id = fhlf.sk_region
    JOIN datalake_quintoandar.aux_date AS dd
        ON dd.id_date = fhlf.sk_prospect_date
    WHERE
        fhlf.mkt_origin IN ('Indica Aí - General', 'Indica Aí - Agents', 'Doorman')
        AND dr.city_group IS NOT NULL
        AND fhlf.sk_prospect_date > 0 
    GROUP BY 1,2,3
),
dim_distinct AS (
	SELECT DISTINCT
	 	dd.date,
	 	dd.week_start,
	 	'Indica Aí - General' AS mkt_origin,
	 	dr.city_group
	FROM
	 	datalake_quintoandar.aux_date AS dd, datalake_region.region AS dr
	WHERE
	    dd.date < CURRENT_DATE
	    
    UNION ALL
    
    SELECT DISTINCT
	 	dd.date,
	 	dd.week_start,
	 	'Indica Aí - Agents' AS mkt_origin,
	 	dr.city_group
	FROM
	 	datalake_quintoandar.aux_date AS dd, datalake_region.region AS dr
	WHERE
	    dd.date < CURRENT_DATE
	    
    UNION ALL
    
    SELECT DISTINCT
	 	dd.date,
	 	dd.week_start,
	 	'Doorman' AS mkt_origin,
	 	dr.city_group
	FROM
	 	datalake_quintoandar.aux_date AS dd, datalake_region.region AS dr
	WHERE
	    dd.date < CURRENT_DATE
),
temp AS ( --Calculo do share por mes
	SELECT DISTINCT
	    ddt.week_start,
	    ddt.city_group,
	    ddt.mkt_origin,
	    (CAST((SUM(row_count) OVER (PARTITION BY ddt.week_start, ddt.city_group, ddt.mkt_origin)) AS double)
	    /
		CAST((SUM(row_count) OVER (PARTITION BY ddt.week_start)) AS double)
	   	) AS current_share
	FROM
		dim_distinct AS ddt
		LEFT JOIN t_row_count AS t
			ON ddt.week_start = t.week_start
			AND ddt.city_group = t.city_group
			AND ddt.mkt_origin = t.mkt_origin
	WHERE ddt.date >= CURRENT_DATE - INTERVAL '3' MONTH
),
share AS (
	SELECT
		*,
		LEAD(current_share,1) OVER (PARTITION BY city_group, mkt_origin ORDER BY week_start DESC) AS share --pegando o share do ultimo mês
	FROM temp
)
SELECT
	date_format(d.date,'yyyy-MM-dd') AS dt, 
	'{id_rule}' AS id_rule,
	d.city_group,
	d.mkt_origin,
	COALESCE(s.share,0) AS share
FROM
	dim_distinct AS d
	JOIN share AS s
		ON d.week_start=s.week_start
		AND d.city_group=s.city_group
		AND d.mkt_origin=s.mkt_origin
ORDER BY 1 DESC,3, 4