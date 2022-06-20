WITH
ciq_results AS (
    SELECT
        DATE_FORMAT(ptn.ts_created, 'yyyyMMdd') as id_date,
        DATE_TRUNC('WEEK', ptn.ts_created) as week_start,
        rgn.city_group,
        COUNT(DISTINCT ptn.id) ciq_count
    FROM
        datalake_ebdb_clean.partner AS ptn
    INNER JOIN
		datalake_region.region AS rgn
            ON ptn.city = rgn.city_name
    WHERE
        ptn.type = 'AUTONOMOUS_AGENT'
        AND NULLIF(rgn.city_group,'') IS NOT NULL
    GROUP BY 1,2,3
),
date_region_cross_join AS(
	SELECT
	    adt.id_date,
		adt.week_start,
		rgn.city_group
	FROM
		datalake_quintoandar.aux_date AS adt
	INNER JOIN
		datalake_region.region AS rgn
			ON adt.date BETWEEN DATE('2021-02-15') AND CURRENT_DATE
	GROUP BY 1,2,3
),
date_region_ciq AS ( --todas as combinações possíveis
	SELECT
		drj.week_start,
		drj.city_group,
        SUM(ciq.ciq_count) ciq_count
	FROM
		date_region_cross_join AS drj
	LEFT JOIN
		ciq_results AS ciq
			ON drj.week_start = ciq.week_start
			AND drj.city_group = ciq.city_group
	GROUP BY 1,2
),
weekly_ciq_share AS ( --Calculo do share por semana
	SELECT
		drc.week_start,
		drc.city_group,
		(
			SUM(drc.ciq_count) OVER(PARTITION BY drc.week_start, drc.city_group)/
			SUM(drc.ciq_count) OVER(PARTITION BY drc.week_start)
		) AS current_share
	FROM
        date_region_ciq AS drc
),
previous_week_share AS (--pegando o share da ultima semana
	SELECT
		wcs.week_start,
		wcs.city_group,
		wcs.current_share,
		LAG(wcs.current_share, 1) OVER(PARTITION BY wcs.city_group ORDER BY wcs.week_start) AS share
	FROM
		weekly_ciq_share AS wcs
)
SELECT DISTINCT
	drj.id_date,
	'{id_rule}' AS id_rule,
	drj.city_group,
	COALESCE(pws.share, 0) AS share,
	'partners' AS funnel_side
FROM
	date_region_cross_join AS drj
INNER JOIN
	previous_week_share AS pws
		ON drj.week_start = pws.week_start
		AND drj.city_group = pws.city_group
WHERE
    drj.week_start > DATE('2021-02-15')