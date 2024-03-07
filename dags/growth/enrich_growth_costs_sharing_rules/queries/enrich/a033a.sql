WITH 
t_row_count AS (
    SELECT
        dd.week_start,
        dr.city_group,
        COUNT(1) AS row_count
    FROM
        dw_public.fact_house_listing_flows AS fhlf
    JOIN datalake_region.region AS dr
        ON dr.id = fhlf.sk_region
    JOIN datalake_quintoandar.aux_date AS dd
        ON dd.id_date = fhlf.sk_prospect_date
    WHERE
        fhlf.mkt_origin = 'Doorman'
        AND dr.id_country = 1
        AND fhlf.sk_prospect_date > 0
    GROUP BY 1,2
),
dim_distinct AS (
	SELECT DISTINCT
	 	dd.date,
	 	dd.week_start,
	 	dr.city_group
	FROM
	 	datalake_quintoandar.aux_date AS dd
	CROSS JOIN datalake_region.region AS dr
	WHERE
	    dd.date BETWEEN DATE('2022-06-01') AND CURRENT_DATE
		AND dr.id_country = 1
),
temp AS (
	SELECT DISTINCT
	    ddt.week_start,
	    ddt.city_group,
	    (CAST((SUM(row_count) OVER (PARTITION BY ddt.week_start, ddt.city_group)) AS DOUBLE)
	    /
		CAST((SUM(row_count) OVER (PARTITION BY ddt.week_start)) AS DOUBLE)
	   	) AS current_share
	FROM
		dim_distinct AS ddt
	LEFT JOIN t_row_count AS t
		ON ddt.week_start = t.week_start
		AND ddt.city_group = t.city_group
),
share AS (
	SELECT
		*,
		LEAD(current_share,1) OVER (PARTITION BY city_group ORDER BY week_start DESC) AS share
	FROM temp
)
SELECT
	INT(YEAR(d.date)*10000 + MONTH(d.date)*100 + DAY(d.date)) AS id_date,
	'{id_rule}' AS id_rule,
	d.city_group,
	COALESCE(s.share,0) AS share,
	'affiliates' AS funnel_side,
	CAST(NULL AS STRING) AS business_context
FROM
	dim_distinct AS d
JOIN 
	share AS s
		ON d.week_start=s.week_start
		AND d.city_group=s.city_group
