WITH share_local_holidays_by_city_group AS (
WITH holidays_by_city_name AS (
	SELECT DISTINCT
		dd.date,
		dd.week_start,
		COALESCE(hs.weekday_name, dd.weekday_name) AS weekday_name,
		NULLIF(hs.mkt_channel, '') AS mkt_channel,
		COALESCE(NULLIF(lh.city_group, ''), dr.city_group) AS city_group,
		COALESCE(NULLIF(lh.city_name, ''), dr.city_name) AS city_name,
		COALESCE(MAX(CAST(REPLACE(cs.share,',','') AS FLOAT)), 0) AS share_city_name,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday'
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.prospect,',','') AS FLOAT)
			 ELSE NULL END AS prospect_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.qualified,',','') AS FLOAT)
			 ELSE NULL END AS qualified_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.opportunity,',','') AS FLOAT)
			 ELSE NULL END AS opportunity_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.first_listings,',','') AS FLOAT)
			 ELSE NULL END AS first_listings_share_holiday
	FROM dim_date dd
	CROSS JOIN dim_region dr
	LEFT JOIN datalake_gsheets_clean_prod.local_holidays lh
	  ON dd.date = DATE(REPLACE(lh.date,'-',''))
	  AND (lh.short_region_name = dr.short_region_name
	  	OR lh.city_group = dr.city_group)
	LEFT JOIN datalake_gsheets_clean_prod.city_share cs
	  ON COALESCE(NULLIF(lh.city_name, ''), dr.city_name) = NULLIF(cs.city_name, '')
	LEFT JOIN datalake_gsheets_clean_prod.weekday_holiday_share_supply hs
	  ON hs.weekday_name = dd.weekday_name
	WHERE dd.date BETWEEN '2018-12-31' AND CURRENT_DATE + INTERVAL '6 months'
	GROUP BY dd.date,
		dd.week_start,
		lh.city_group,
		lh.short_region_name,
		dr.city_group,
		lh.city_name,
		dr.city_name,
		hs.weekday_name,
		dd.weekday_name,
		dd.is_brz_holiday,
		hs.mkt_channel,
		hs.prospect,
		hs.qualified,
		hs.opportunity,
		hs.first_listings
	)
	SELECT 
		date,
		week_start,
		weekday_name,
		mkt_channel,
		city_group,
		SUM(share_city_name * COALESCE(prospect_share_holiday,1)) AS share_holiday_prospect,
		SUM(share_city_name * COALESCE(qualified_share_holiday,1)) AS share_holiday_qualified,
		SUM(share_city_name * COALESCE(opportunity_share_holiday,1)) AS share_holiday_opportunity,
		SUM(share_city_name * COALESCE(first_listings_share_holiday,1)) AS share_holiday_first_listings
	FROM holidays_by_city_name
	WHERE city_group IS NOT NULL
	GROUP BY 1, 2, 3, 4, 5	
), final_shares AS (
SELECT DISTINCT
	lhc.date,
	lhc.week_start,
	wscs.city_group,
	wscs.mkt_channel,
	wscs.lead_context,
	CAST(REPLACE(wscs.prospect,',','') AS FLOAT) AS final_share_wo_holiday_prospect,
	CAST(REPLACE(wscs.prospect,',','') AS FLOAT) * lhc.share_holiday_prospect AS final_share_prospect,
	CAST(REPLACE(wscs.qualified,',','') AS FLOAT) AS final_share_wo_holiday_qualified,
	CAST(REPLACE(wscs.qualified,',','') AS FLOAT) * lhc.share_holiday_qualified AS final_share_qualified,
	CAST(REPLACE(wscs.opportunity,',','') AS FLOAT) AS final_share_wo_holiday_opportunity,
	CAST(REPLACE(wscs.opportunity,',','') AS FLOAT) * lhc.share_holiday_opportunity AS final_share_opportunity,
	CAST(REPLACE(wscs.first_listing,',','') AS FLOAT) AS final_share_wo_holiday_first_listings,
	CAST(REPLACE(wscs.first_listing,',','') AS FLOAT) * lhc.share_holiday_first_listings AS final_share_first_listings
FROM share_local_holidays_by_city_group lhc
LEFT JOIN datalake_gsheets_clean_prod.weekday_supply_channel_share wscs
  ON wscs.weekday = lhc.weekday_name AND wscs.city_group = lhc.city_group AND wscs.mkt_channel = lhc.mkt_channel
), diff_w_and_wo_holiday_share AS (
SELECT
	fsh.date,
	fsh.week_start,
	fsh.city_group,
	fsh.mkt_channel,
	gwvs.mkt_origin,
	fsh.lead_context,
	SUM(fsh.final_share_prospect * CAST(REPLACE(gwvs.prospect,',','') AS FLOAT)) AS prospect_1,
	SUM(fsh.final_share_prospect * CAST(REPLACE(gwvs.prospect,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) AS total_prospect_daily,
	SUM(fsh.final_share_wo_holiday_prospect * CAST(REPLACE(gwvs.prospect,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) AS total_prospect_daily_wo_holiday,
	SUM(fsh.final_share_qualified * CAST(REPLACE(gwvs.qualified,',','') AS FLOAT)) AS qualified_1,
	SUM(fsh.final_share_qualified * CAST(REPLACE(gwvs.qualified,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) AS total_qualified_daily,
	SUM(fsh.final_share_wo_holiday_qualified * CAST(REPLACE(gwvs.qualified,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) AS total_qualified_daily_wo_holiday,
	SUM(fsh.final_share_opportunity * CAST(REPLACE(gwvs.opportunity,',','') AS FLOAT)) AS opportunity_1,
	SUM(fsh.final_share_opportunity * CAST(REPLACE(gwvs.opportunity,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) AS total_opportunity_daily,
	SUM(fsh.final_share_wo_holiday_opportunity * CAST(REPLACE(gwvs.opportunity,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) AS total_opportunity_daily_wo_holiday,
	SUM(fsh.final_share_first_listings * CAST(REPLACE(gwvs.first_listing,',','') AS FLOAT)) AS first_listing_1,
	SUM(fsh.final_share_first_listings * CAST(REPLACE(gwvs.first_listing,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) AS total_first_listing_daily,
	SUM(fsh.final_share_wo_holiday_first_listings * CAST(REPLACE(gwvs.first_listing,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) AS total_first_listing_daily_wo_holiday
FROM final_shares fsh
JOIN datalake_gsheets_clean_prod.week_volumes_supply gwvs
  ON fsh.mkt_channel = gwvs.mkt_channel
  	AND fsh.lead_context = gwvs.lead_context
  	AND fsh.week_start = gwvs.week_start
  	AND fsh.city_group = gwvs.city_group
GROUP BY 1, 2, 3, 4, 5, 6,
	fsh.final_share_prospect,
	gwvs.prospect,
	fsh.final_share_wo_holiday_prospect,
	fsh.final_share_qualified,
	gwvs.qualified,
	fsh.final_share_wo_holiday_qualified,
	fsh.final_share_opportunity,
	gwvs.opportunity,
	fsh.final_share_wo_holiday_opportunity,
	fsh.final_share_first_listings,
	gwvs.first_listing,
	fsh.final_share_wo_holiday_first_listings
), daily_target_shares AS (
SELECT 
	date,
	week_start,
	city_group,
	mkt_channel,
	mkt_origin,
	lead_context,
	prospect_1 + CASE WHEN total_prospect_daily > 0 THEN (total_prospect_daily_wo_holiday - total_prospect_daily) * prospect_1 / total_prospect_daily ELSE 0 END AS prospect,
	qualified_1 + CASE WHEN total_qualified_daily > 0 THEN (total_qualified_daily_wo_holiday - total_qualified_daily) * qualified_1 / total_qualified_daily ELSE 0 END AS qualified,
	opportunity_1 + CASE WHEN total_opportunity_daily > 0 THEN (total_opportunity_daily_wo_holiday - total_opportunity_daily) * opportunity_1 / total_opportunity_daily ELSE 0 END AS opportunity,
	first_listing_1 + CASE WHEN total_first_listing_daily > 0 THEN (total_first_listing_daily_wo_holiday - total_first_listing_daily) * first_listing_1 / total_first_listing_daily ELSE 0 END AS first_listing
FROM diff_w_and_wo_holiday_share 
), gsheets_supply_target_adjusted AS (
	WITH
	supply_targets AS (
		SELECT * FROM datalake_gsheets_clean_prod.supply_targets_2021 
	    UNION ALL
	    	SELECT * FROM datalake_gsheets_clean_prod.supply_targets_2020 
	    UNION ALL
	        SELECT * FROM datalake_gsheets_clean_prod.supply_targets_2019
	)
	SELECT
	  	dt_target AS date,
		dt_week_started AS week_start,
		NULLIF(city_group, '') AS city_group,
		NULLIF(supply_channel, '') AS mkt_channel,
		NULLIF(supply_origin, '') AS mkt_origin,
		NULLIF(lead_context, '') AS lead_context,
		CAST(REPLACE(prospects,',','') AS FLOAT) AS prospect,
		CAST(REPLACE(qualifieds,',','') AS FLOAT) AS qualified,
		CAST(REPLACE(opportunities,',','') AS FLOAT) AS opportunity,
		CAST(REPLACE(first_listings,',','') AS FLOAT) AS first_listing
	FROM supply_targets
	WHERE DATE_TRUNC('month', dt_target) <= DATE_TRUNC('month', CURRENT_DATE)
), past_targets AS (
SELECT
	week_start,
	city_group,
	mkt_channel,
	mkt_origin,
	lead_context,
	SUM(prospect) AS pp_congelado,
	SUM(qualified) AS ql_congelado,
	SUM(opportunity) AS op_congelado,
	SUM(first_listing) AS fl_congelado
FROM gsheets_supply_target_adjusted
GROUP BY 1, 2, 3, 4, 5
), calculated_targets AS (
SELECT
	week_start,
	city_group,
	mkt_channel,
	mkt_origin,
	lead_context,
	SUM(prospect) AS pp_calculado,
	SUM(qualified) AS ql_calculado,
	SUM(opportunity) AS op_calculado,
	SUM(first_listing) AS fl_calculado
FROM daily_target_shares
GROUP BY 1, 2, 3, 4, 5
), targets_diff AS (
SELECT
	ct.week_start,
	ct.city_group,
	ct.mkt_channel,
	ct.mkt_origin,
	ct.lead_context,
	COALESCE(ct.pp_calculado,0) - COALESCE(pt.pp_congelado,0) AS diff_pp,
	COALESCE(ct.ql_calculado,0) - COALESCE(pt.ql_congelado,0) AS diff_ql,
	COALESCE(ct.op_calculado,0) - COALESCE(pt.op_congelado,0) AS diff_op,
	COALESCE(ct.fl_calculado,0) - COALESCE(pt.fl_congelado,0) AS diff_fl
FROM calculated_targets ct
LEFT JOIN past_targets pt
  ON ct.week_start = pt.week_start
    AND ct.city_group = pt.city_group
	AND ct.mkt_channel = pt.mkt_channel
	AND ct.mkt_origin = pt.mkt_origin
	AND ct.lead_context = pt.lead_context
), calculated_targets_week_month AS (
SELECT
	date,
	week_start,
	city_group,
	mkt_channel,
	mkt_origin,
	lead_context,
	SUM(prospect) AS pp_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN prospect ELSE 0 END) OVER(PARTITION BY week_start, city_group, mkt_channel, mkt_origin, lead_context) AS pp_total_week,
	SUM(qualified) AS ql_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN qualified ELSE 0 END) OVER(PARTITION BY week_start, city_group, mkt_channel, mkt_origin, lead_context) AS ql_total_week,
	SUM(opportunity) AS op_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN opportunity ELSE 0 END) OVER(PARTITION BY week_start, city_group, mkt_channel, mkt_origin, lead_context) AS op_total_week,
	SUM(first_listing) AS fl_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN first_listing ELSE 0 END) OVER(PARTITION BY week_start, city_group, mkt_channel, mkt_origin, lead_context) AS fl_total_week
FROM daily_target_shares
GROUP BY 1, 2, 3, 4, 5, 6, prospect, qualified, opportunity, first_listing
), daily_target_shares_adjusted AS (
SELECT DISTINCT
	COALESCE(g.date, d.date) AS date,
	COALESCE(g.week_start, d.week_start) AS week_start,
	COALESCE(g.city_group, d.city_group) AS city_group,
	COALESCE(g.mkt_channel, d.mkt_channel) AS mkt_channel,
	COALESCE(g.mkt_origin, d.mkt_origin) AS mkt_origin,
	COALESCE(g.lead_context, d.lead_context) AS lead_context,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.prospect
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.pp_total_week != 0 AND td.diff_pp != 0 THEN td.diff_pp * COALESCE(wm.pp_calculado,0)/wm.pp_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.pp_total_week = 0 AND td.diff_pp != 0 THEN td.diff_pp
		 ELSE d.prospect END AS prospect,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.qualified
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.ql_total_week != 0 AND td.diff_ql != 0 THEN td.diff_ql * COALESCE(wm.ql_calculado,0)/wm.ql_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.ql_total_week = 0 AND td.diff_ql != 0 THEN td.diff_ql
		 ELSE d.qualified END AS qualified,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.opportunity
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.op_total_week != 0 AND td.diff_op != 0 THEN td.diff_op * COALESCE(wm.op_calculado,0)/wm.op_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.op_total_week = 0 AND td.diff_op != 0 THEN td.diff_op
		 ELSE d.opportunity END AS opportunity,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.first_listing
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.fl_total_week != 0 AND td.diff_fl != 0 THEN td.diff_fl * COALESCE(wm.fl_calculado,0)/wm.fl_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.fl_total_week = 0 AND td.diff_fl != 0 THEN td.diff_fl
		 ELSE d.first_listing END AS first_listing
FROM daily_target_shares d
FULL OUTER JOIN gsheets_supply_target_adjusted g
  ON d.date = g.date
	AND d.week_start = g.week_start
	AND d.city_group = g.city_group
	AND d.mkt_channel = g.mkt_channel
	AND d.mkt_origin = g.mkt_origin
	AND d.lead_context = g.lead_context
LEFT JOIN targets_diff td
  ON td.week_start = d.week_start
    AND d.city_group = td.city_group
	AND d.mkt_channel = td.mkt_channel
	AND d.mkt_origin = td.mkt_origin
	AND d.lead_context = td.lead_context
LEFT JOIN calculated_targets_week_month wm
  ON wm.date = d.date
    AND wm.week_start = d.week_start
    AND wm.city_group = d.city_group
    AND wm.mkt_channel = d.mkt_channel
    AND wm.mkt_origin = d.mkt_origin
    AND wm.lead_context = d.lead_context
), negative_targets AS (
SELECT
	date,
	SUM(CASE WHEN prospect < 0 THEN prospect END) AS pp_negative,
	SUM(CASE WHEN qualified < 0 THEN qualified END) AS ql_negative,
	SUM(CASE WHEN opportunity < 0 THEN opportunity END) AS op_negative,
	SUM(CASE WHEN first_listing < 0 THEN first_listing END) AS fl_negative
FROM daily_target_shares_adjusted
GROUP BY 1
)
SELECT
	dt.date,
	week_start,
	city_group,
	mkt_channel AS supply_channel,
	mkt_origin AS supply_origin,
	lead_context,
	CASE WHEN prospect <= 0 THEN 0 ELSE prospect + COALESCE(nt.pp_negative,0) * prospect/(SUM(CASE WHEN prospect > 0 THEN prospect END) OVER(PARTITION BY dt.date)) END AS prospect,
	CASE WHEN qualified <= 0 THEN 0 ELSE qualified + COALESCE(nt.ql_negative,0) * qualified/(SUM(CASE WHEN qualified > 0 THEN qualified END) OVER(PARTITION BY dt.date)) END AS qualified,
	CASE WHEN opportunity <= 0 THEN 0 ELSE opportunity + COALESCE(nt.op_negative,0) * opportunity/(SUM(CASE WHEN opportunity > 0 THEN opportunity END) OVER(PARTITION BY dt.date)) END AS opportunity,
	CASE WHEN first_listing <= 0 THEN 0 ELSE first_listing + COALESCE(nt.fl_negative,0) * first_listing/(SUM(CASE WHEN first_listing > 0 THEN first_listing END) OVER(PARTITION BY dt.date)) END AS first_listing
FROM daily_target_shares_adjusted dt
JOIN negative_targets nt
  ON dt.date = nt.date