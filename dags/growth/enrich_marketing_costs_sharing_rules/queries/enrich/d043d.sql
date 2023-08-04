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
),
----------------------------------------------------------------------------
-- In case of get 0 results on that day a fall back share will be applied --
----------------------------------------------------------------------------
fall_back(city_group, share) AS (
    SELECT 'Campinas', 0.36 UNION ALL
    SELECT 'Curitiba', 0.22 UNION ALL
    SELECT 'Florianópolis', 0.22 UNION ALL
    SELECT 'Santos', 0.20 
), 
fall_back_dated AS ( 
	SELECT 
		adt.id_date,
		'{id_rule}' AS id_rule,
		city_group, 
		share, 
		'demand' AS funnel_side
	FROM fall_back AS fb 
	CROSS JOIN datalake_quintoandar.aux_date AS adt
),
---------------------------------------------------------
-- Getting the real share based on the previous result --
---------------------------------------------------------
real AS (
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
), 
-------------------------------------------------------------------------------------------
-- Creating a validator metric that will set which table the share value will come from --
-------------------------------------------------------------------------------------------
validacao AS (
SELECT 
	adt.id_date, 
	COUNT(DISTINCT id) AS validador
FROM datalake_quintoandar.aux_date AS adt
LEFT JOIN
	tof_events AS tof
		ON DATE(tof.ts_interaction) = adt.date
		AND tof.utm_campaign = 'd043d.D.RET.Rent.High_WAS.churnedTPs'
		AND tof.city_group IN ('Campinas', 'Curitiba', 'Florianópolis', 'Santos')
GROUP BY 1 
) 
-------------------------------------------------------------------------------------------------------
-- Applying share factor from the correct table based on status: it has or hasn't result on that day --
-------------------------------------------------------------------------------------------------------
SELECT DISTINCT 
	v.id_date, 
	'{id_rule}' AS id_rule,
	CASE
		WHEN validador > 0 THEN r.city_group
		ELSE fb.city_group
	END AS city_group, 
	CASE
		WHEN validador > 0 THEN r.share
		ELSE fb.share
	END AS share, 
	'demand' AS funnel_side,
	CAST(NULL AS STRING) AS business_context
FROM validacao v
LEFT JOIN real AS r 
	ON r.id_date = v.id_date 
LEFT JOIN fall_back_dated AS fb 
	ON fb.id_date = v.id_date 