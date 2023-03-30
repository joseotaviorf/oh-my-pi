WITH
tof_events AS (
	SELECT
		ui.id,
		ui.sk_region,
		ui.utm_campaign,
		ui.ts_event AS ts_interaction,
		rgn.city_group
	FROM
	    datalake_top_of_funnel_demand.user_interactions AS ui
	INNER JOIN
    	datalake_region.region AS rgn
        	ON rgn.id = ui.sk_region
)
SELECT
	adt.id_date,
	'{id_rule}' AS id_rule,
	tof.city_group,
	FLOAT(COUNT(DISTINCT tof.id)/NULLIF(SUM(COUNT(DISTINCT tof.id)) OVER(PARTITION BY adt.id_date), 0)) AS share,
	'demand' AS funnel_side
FROM
	tof_events AS tof
INNER JOIN
	datalake_quintoandar.aux_date AS adt
		ON DATE(tof.ts_interaction) = adt.date
WHERE 1=1
	AND tof.utm_campaign = 'd043d.D.RET.Rent.High_WAS.churnedTPs'
	AND tof.city_group IN ('Campinas', 'Curitiba', 'Florianópolis', 'Santos')
GROUP BY
	1,2,3