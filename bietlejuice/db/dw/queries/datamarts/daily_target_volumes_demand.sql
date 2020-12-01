WITH share_local_holidays_by_city_group AS (
WITH holidays_by_city_name AS (
	SELECT DISTINCT
		dd.date,
		dd.week_start,
		COALESCE(hs.weekday_name, dd.weekday_name) AS weekday_name,
		COALESCE(NULLIF(lh.city_group, ''), dr.city_group) AS city_group,
		COALESCE(NULLIF(lh.city_name, ''), dr.city_name) AS city_name,
		COALESCE(MAX(CAST(REPLACE(cs.share,',','') AS FLOAT)), 0) AS share_city_name,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.visit_booked,',','') AS FLOAT)
			 ELSE NULL END AS visit_booked_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.visit_completed,',','') AS FLOAT)
			 ELSE NULL END AS visit_completed_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.offer_submitted,',','') AS FLOAT)
			 ELSE NULL END AS offer_submitted_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.offer_accepted,',','') AS FLOAT)
			 ELSE NULL END AS offer_accepted_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.document_sent,',','') AS FLOAT)
			 ELSE NULL END AS document_sent_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday' 
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.credit_approved,',','') AS FLOAT)
			 ELSE NULL END AS credit_approved_share_holiday,
		CASE
			WHEN dd.is_brz_holiday = 'Holiday'
			OR NULLIF(lh.city_group, '') IS NOT NULL
			OR NULLIF(lh.short_region_name, '') IS NOT NULL THEN CAST(REPLACE(hs.contract_signed,',','') AS FLOAT)
			 ELSE NULL END AS contract_signed_share_holiday
	FROM dim_date dd
	CROSS JOIN dim_region dr
	LEFT JOIN datalake_raw.gsheets_local_holidays lh
	  ON dd.date = DATE(REPLACE(lh.date,'-',''))
	  AND (lh.short_region_name = dr.short_region_name
	  	OR lh.city_group = dr.city_group)
	LEFT JOIN datalake_raw.gsheets_city_share cs
	  ON COALESCE(NULLIF(lh.city_name, ''), dr.city_name) = NULLIF(cs.city_name, '')
	LEFT JOIN datalake_raw.gsheets_weekday_holiday_share hs
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
		hs.visit_booked,
		hs.visit_completed,
		hs.offer_submitted,
		hs.offer_accepted,
		hs.document_sent,
		hs.credit_approved,
		hs.contract_signed
	)
	SELECT 
		date,
		week_start,
		weekday_name,
		city_group,
		SUM(share_city_name * COALESCE(visit_booked_share_holiday,1)) AS share_holiday_visit_booked,
		SUM(share_city_name * COALESCE(visit_completed_share_holiday,1)) AS share_holiday_visit_completed,
		SUM(share_city_name * COALESCE(offer_submitted_share_holiday,1)) AS share_holiday_offer_submitted,
		SUM(share_city_name * COALESCE(offer_accepted_share_holiday,1)) AS share_holiday_offer_accepted,
		SUM(share_city_name * COALESCE(document_sent_share_holiday,1)) AS share_holiday_document_sent,
		SUM(share_city_name * COALESCE(credit_approved_share_holiday,1)) AS share_holiday_credit_approved,
		SUM(share_city_name * COALESCE(contract_signed_share_holiday,1)) AS share_holiday_contract_signed
	FROM holidays_by_city_name
	WHERE city_group IS NOT NULL
	GROUP BY 1, 2, 3, 4
), final_shares AS (
SELECT DISTINCT
	lhc.date,
	lhc.week_start,
	wd.city_group,
	wd.demand_channel_type,
	dcs.demand_channel,
	wd.funnel_first_touchpoint,
	CAST(REPLACE(wd.visit_booked,',','') AS FLOAT) * CAST(REPLACE(dcs.visit_booked,',','') AS FLOAT) AS final_share_wo_holiday_visits_booked,
	CAST(REPLACE(wd.visit_booked,',','') AS FLOAT) * lhc.share_holiday_visit_booked * CAST(REPLACE(dcs.visit_booked,',','') AS FLOAT) AS final_share_visits_booked,
	CAST(REPLACE(wd.visit_completed,',','') AS FLOAT) * CAST(REPLACE(dcs.visit_completed,',','') AS FLOAT) AS final_share_wo_holiday_visits_completed,
	CAST(REPLACE(wd.visit_completed,',','') AS FLOAT) * lhc.share_holiday_visit_completed * CAST(REPLACE(dcs.visit_completed,',','') AS FLOAT) AS final_share_visits_completed,
	CAST(REPLACE(wd.offer_submitted,',','') AS FLOAT) * CAST(REPLACE(dcs.offer_submitted,',','') AS FLOAT) AS final_share_wo_holiday_offer_submitted,
	CAST(REPLACE(wd.offer_submitted,',','') AS FLOAT) * lhc.share_holiday_offer_submitted * CAST(REPLACE(dcs.offer_submitted,',','') AS FLOAT) AS final_share_offer_submitted,
	CAST(REPLACE(wd.offer_accepted,',','') AS FLOAT) * CAST(REPLACE(dcs.offer_accepted,',','') AS FLOAT) AS final_share_wo_holiday_offer_accepted,
	CAST(REPLACE(wd.offer_accepted,',','') AS FLOAT) * lhc.share_holiday_offer_accepted * CAST(REPLACE(dcs.offer_accepted,',','') AS FLOAT) AS final_share_offer_accepted,
	CAST(REPLACE(wd.credit_evaluation_init,',','') AS FLOAT) * CAST(REPLACE(dcs.credit_evaluation_init,',','') AS FLOAT) AS final_share_wo_holiday_credit_evaluation_init,
	CAST(REPLACE(wd.credit_evaluation_init,',','') AS FLOAT) * lhc.share_holiday_offer_accepted * CAST(REPLACE(dcs.credit_evaluation_init,',','') AS FLOAT) AS final_share_credit_evaluation_init,
	CAST(REPLACE(wd.credit_evaluation_positive,',','') AS FLOAT) * CAST(REPLACE(dcs.credit_evaluation_positive,',','') AS FLOAT) AS final_share_wo_holiday_credit_evaluation_positive,
	CAST(REPLACE(wd.credit_evaluation_positive,',','') AS FLOAT) * lhc.share_holiday_offer_accepted * CAST(REPLACE(dcs.credit_evaluation_positive,',','') AS FLOAT) AS final_share_credit_evaluation_positive,
	CAST(REPLACE(wd.document_sent,',','') AS FLOAT) * CAST(REPLACE(dcs.document_sent,',','') AS FLOAT) AS final_share_wo_holiday_document_sent,
	CAST(REPLACE(wd.document_sent,',','') AS FLOAT) * lhc.share_holiday_document_sent * CAST(REPLACE(dcs.document_sent,',','') AS FLOAT) AS final_share_document_sent,
	CAST(REPLACE(wd.credit_approved,',','') AS FLOAT) * CAST(REPLACE(dcs.credit_approved,',','') AS FLOAT) AS final_share_wo_holiday_credit_approved,
	CAST(REPLACE(wd.credit_approved,',','') AS FLOAT) * lhc.share_holiday_credit_approved * CAST(REPLACE(dcs.credit_approved,',','') AS FLOAT) AS final_share_credit_approved,
	CAST(REPLACE(wd.contract_signed,',','') AS FLOAT) * CAST(REPLACE(dcs.contract_signed,',','') AS FLOAT) AS final_share_wo_holiday_contract_signed,
	CAST(REPLACE(wd.contract_signed,',','') AS FLOAT) * lhc.share_holiday_contract_signed * CAST(REPLACE(dcs.contract_signed,',','') AS FLOAT) AS final_share_contract_signed
FROM share_local_holidays_by_city_group lhc
LEFT JOIN datalake_raw.gsheets_weekday_demand_share wd
  ON wd.weekday_name = lhc.weekday_name AND wd.city_group = lhc.city_group
LEFT JOIN datalake_raw.gsheets_demand_channel_share dcs
  ON dcs.city_group = lhc.city_group AND CAST(REPLACE(dcs.week_start,'-','') AS date) = lhc.week_start
), diff_w_and_wo_holiday_share AS (
SELECT
	fsh.date,
	fsh.week_start,
	fsh.city_group,
	fsh.demand_channel_type,
	fsh.demand_channel,
	wv.guarantee,
	fsh.funnel_first_touchpoint,
	SUM(fsh.final_share_visits_booked * CAST(REPLACE(wv.visit_booked,',','') AS FLOAT)) AS visit_booked_1,
	SUM(fsh.final_share_visits_booked * CAST(REPLACE(wv.visit_booked,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_visit_booked_daily,
	SUM(fsh.final_share_wo_holiday_visits_booked * CAST(REPLACE(wv.visit_booked,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_visit_booked_daily_wo_holiday,
	SUM(fsh.final_share_visits_completed * CAST(REPLACE(wv.visit_completed,',','') AS FLOAT)) AS visit_completed_1,
	SUM(fsh.final_share_visits_completed * CAST(REPLACE(wv.visit_completed,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_visit_completed_daily,
	SUM(fsh.final_share_wo_holiday_visits_completed * CAST(REPLACE(wv.visit_completed,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_visit_completed_daily_wo_holiday,
	SUM(fsh.final_share_offer_submitted * CAST(REPLACE(wv.offer_submitted,',','') AS FLOAT)) AS offer_submitted_1,
	SUM(fsh.final_share_offer_submitted * CAST(REPLACE(wv.offer_submitted,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_offer_submitted_daily,
	SUM(fsh.final_share_wo_holiday_offer_submitted * CAST(REPLACE(wv.offer_submitted,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_offer_submitted_daily_wo_holiday,
	SUM(fsh.final_share_offer_accepted * CAST(REPLACE(wv.offer_accepted,',','') AS FLOAT)) AS offer_accepted_1,
	SUM(fsh.final_share_offer_accepted * CAST(REPLACE(wv.offer_accepted,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_offer_accepted_daily,
	SUM(fsh.final_share_wo_holiday_offer_accepted * CAST(REPLACE(wv.offer_accepted,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_offer_accepted_daily_wo_holiday,
	SUM(fsh.final_share_credit_evaluation_init * CAST(REPLACE(wv.credit_evaluation_init,',','') AS FLOAT)) AS credit_evaluation_init_1,
	SUM(fsh.final_share_credit_evaluation_init * CAST(REPLACE(wv.credit_evaluation_init,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_credit_evaluation_init_daily,
	SUM(fsh.final_share_wo_holiday_credit_evaluation_init * CAST(REPLACE(wv.credit_evaluation_init,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_credit_evaluation_init_daily_wo_holiday,
	SUM(fsh.final_share_credit_evaluation_positive * CAST(REPLACE(wv.credit_evaluation_positive,',','') AS FLOAT)) AS credit_evaluation_positive_1,
	SUM(fsh.final_share_credit_evaluation_positive * CAST(REPLACE(wv.credit_evaluation_positive,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_credit_evaluation_positive_daily,
	SUM(fsh.final_share_wo_holiday_credit_evaluation_positive * CAST(REPLACE(wv.credit_evaluation_positive,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_credit_evaluation_positive_daily_wo_holiday,
	SUM(fsh.final_share_document_sent * CAST(REPLACE(wv.document_sent,',','') AS FLOAT)) AS document_sent_1,
	SUM(fsh.final_share_document_sent * CAST(REPLACE(wv.document_sent,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_document_sent_daily,
	SUM(fsh.final_share_wo_holiday_document_sent * CAST(REPLACE(wv.document_sent,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_document_sent_daily_wo_holiday,
	SUM(fsh.final_share_credit_approved * CAST(REPLACE(wv.credit_approved,',','') AS FLOAT)) AS credit_approved_1,
	SUM(fsh.final_share_credit_approved * CAST(REPLACE(wv.credit_approved,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_credit_approved_daily,
	SUM(fsh.final_share_wo_holiday_credit_approved * CAST(REPLACE(wv.credit_approved,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_credit_approved_daily_wo_holiday,
	SUM(fsh.final_share_contract_signed * CAST(REPLACE(wv.contract_signed,',','') AS FLOAT)) AS contract_signed_1,
	SUM(fsh.final_share_contract_signed * CAST(REPLACE(wv.contract_signed,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_contract_signed_daily,
	SUM(fsh.final_share_wo_holiday_contract_signed * CAST(REPLACE(wv.contract_signed,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_contract_signed_daily_wo_holiday,
	SUM(fsh.final_share_visits_booked * CAST(REPLACE(wv.new_tenant_prospect,',','') AS FLOAT)) AS new_tenant_prospect_1,
	SUM(fsh.final_share_visits_booked * CAST(REPLACE(wv.new_tenant_prospect,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_new_tenant_prospect_daily,
	SUM(fsh.final_share_wo_holiday_visits_booked * CAST(REPLACE(wv.new_tenant_prospect,',','') AS FLOAT)) OVER(PARTITION BY fsh.week_start, fsh.city_group, fsh.demand_channel_type, fsh.demand_channel, fsh.funnel_first_touchpoint) AS total_new_tenant_prospect_daily_wo_holiday
FROM final_shares fsh
JOIN datalake_raw.gsheets_week_volumes_demand wv
  ON fsh.city_group = wv.city_group
  	AND fsh.week_start = CAST(REPLACE(wv.week_start,'-','') AS date)
  	AND fsh.demand_channel_type = wv.demand_channel_type
  	AND fsh.funnel_first_touchpoint = wv.funnel_first_touchpoint
GROUP BY 1, 2, 3, 4, 5, 6, 7,
	fsh.final_share_visits_booked,
	wv.visit_booked,
	fsh.final_share_wo_holiday_visits_booked,
	fsh.final_share_visits_completed,
	wv.visit_completed,
	fsh.final_share_wo_holiday_visits_completed,
	fsh.final_share_credit_approved,
	wv.credit_approved,
	fsh.final_share_wo_holiday_credit_approved,
	fsh.final_share_contract_signed,
	wv.contract_signed,
	fsh.final_share_wo_holiday_contract_signed,
	fsh.final_share_offer_submitted,
	wv.offer_submitted,
	fsh.final_share_wo_holiday_offer_submitted,
	fsh.final_share_offer_accepted,
	wv.offer_accepted,
	fsh.final_share_wo_holiday_offer_accepted,
	fsh.final_share_credit_evaluation_init,
	wv.credit_evaluation_init,
	fsh.final_share_wo_holiday_credit_evaluation_init,
	fsh.final_share_credit_evaluation_positive,
	wv.credit_evaluation_positive,
	fsh.final_share_wo_holiday_credit_evaluation_positive,
	fsh.final_share_document_sent,
	wv.document_sent,
	fsh.final_share_wo_holiday_document_sent,
	wv.new_tenant_prospect
), daily_target_shares AS (
SELECT 
	date,
	week_start,
	city_group,
	demand_channel_type,
	demand_channel,
	funnel_first_touchpoint,
	guarantee,
	visit_booked_1 + CASE WHEN total_visit_booked_daily > 0 THEN (total_visit_booked_daily_wo_holiday - total_visit_booked_daily) * visit_booked_1 / total_visit_booked_daily ELSE 0 END AS visit_booked,
	visit_completed_1 + CASE WHEN total_visit_completed_daily > 0 THEN (total_visit_completed_daily_wo_holiday - total_visit_completed_daily) * visit_completed_1 / total_visit_completed_daily ELSE 0 END AS visit_completed,
	offer_submitted_1 + CASE WHEN total_offer_submitted_daily > 0 THEN (total_offer_submitted_daily_wo_holiday - total_offer_submitted_daily) * offer_submitted_1 / total_offer_submitted_daily ELSE 0 END AS offer_submitted,
	offer_accepted_1 + CASE WHEN total_offer_accepted_daily > 0 THEN (total_offer_accepted_daily_wo_holiday - total_offer_accepted_daily) * offer_accepted_1 / total_offer_accepted_daily ELSE 0 END AS offer_accepted,
	credit_evaluation_init_1 + CASE WHEN total_credit_evaluation_init_daily > 0 THEN (total_credit_evaluation_init_daily_wo_holiday - total_credit_evaluation_init_daily) * credit_evaluation_init_1 / total_credit_evaluation_init_daily ELSE 0 END AS credit_evaluation_init,
	credit_evaluation_positive_1 + CASE WHEN total_credit_evaluation_positive_daily > 0 THEN (total_credit_evaluation_positive_daily_wo_holiday - total_credit_evaluation_positive_daily) * credit_evaluation_positive_1 / total_credit_evaluation_positive_daily ELSE 0 END AS credit_evaluation_positive,
	document_sent_1 + CASE WHEN total_document_sent_daily > 0 THEN (total_document_sent_daily_wo_holiday - total_document_sent_daily) * document_sent_1 / total_document_sent_daily ELSE 0 END AS document_sent,
	credit_approved_1 + CASE WHEN total_credit_approved_daily > 0 THEN (total_credit_approved_daily_wo_holiday - total_credit_approved_daily) * credit_approved_1 / total_credit_approved_daily ELSE 0 END AS credit_approved,
	contract_signed_1 + CASE WHEN total_contract_signed_daily > 0 THEN (total_contract_signed_daily_wo_holiday - total_contract_signed_daily) * contract_signed_1 / total_contract_signed_daily ELSE 0 END AS contract_signed,
	new_tenant_prospect_1 + CASE WHEN total_new_tenant_prospect_daily > 0 THEN (total_new_tenant_prospect_daily_wo_holiday - total_new_tenant_prospect_daily) * new_tenant_prospect_1 / total_new_tenant_prospect_daily ELSE 0 END AS new_tenant_prospect
FROM diff_w_and_wo_holiday_share 
), gsheets_demand_target_adjusted AS (
	WITH
	demand_targets AS (
		SELECT * FROM datalake_raw.gsheets_demand_targets_2021 
	    UNION ALL
		    SELECT * FROM datalake_raw.gsheets_demand_targets_2020 
	    UNION ALL
	        SELECT * FROM datalake_raw.gsheets_demand_targets_2019
	)
	SELECT
	    CAST(REPLACE(date,'-','') AS date) AS date,
		CAST(REPLACE(week_start,'-','') AS date) AS week_start,
		NULLIF(city_group, '') AS city_group,
		NULLIF(demand_channel_type, '') AS demand_channel_type,
		NULLIF(demand_channel, '') AS demand_channel,
		NULLIF(funnel_origin, '') AS funnel_first_touchpoint,
		NULLIF(guarantee, '') AS guarantee,
		CAST(REPLACE(visits_booked,',','') AS FLOAT) AS visit_booked,
		CAST(REPLACE(visits_completed,',','') AS FLOAT) AS visit_completed,
		CAST(REPLACE(offer_sent,',','') AS FLOAT) AS offer_submitted,
		CAST(REPLACE(offer_accepted,',','') AS FLOAT) AS offer_accepted,
		CAST(REPLACE(evaluation_started,',','') AS FLOAT) AS credit_evaluation_init,
		CAST(REPLACE(evaluation_positive,',','') AS FLOAT) AS credit_evaluation_positive,
		CAST(REPLACE(doc_sent,',','') AS FLOAT) AS document_sent,
		CAST(REPLACE(credit_approved,',','') AS FLOAT) credit_approved,
		CAST(REPLACE(contracts_signed,',','') AS FLOAT) AS contract_signed,
		CAST(REPLACE(new_tenant_prospects,',','') AS FLOAT) AS new_tenant_prospect
	FROM demand_targets
	WHERE DATE_TRUNC('month', CAST(REPLACE(date,'-','') AS date)) <= DATE_TRUNC('month', CURRENT_DATE)
), past_targets AS (
SELECT
	week_start,
	city_group,
	demand_channel_type,
	demand_channel,
	funnel_first_touchpoint,
	guarantee,
	SUM(visit_booked) AS vb_congelado,
	SUM(visit_completed) AS vc_congelado,
	SUM(offer_submitted) AS os_congelado,
	SUM(offer_accepted) AS oa_congelado,
	SUM(credit_evaluation_init) AS cei_congelado,
	SUM(credit_evaluation_positive) AS cep_congelado,
	SUM(document_sent) AS ds_congelado,
	SUM(credit_approved) AS ca_congelado,
	SUM(contract_signed) AS cs_congelado,
	SUM(new_tenant_prospect) AS ntp_congelado
FROM gsheets_demand_target_adjusted
GROUP BY 1, 2, 3, 4, 5, 6
), calculated_targets AS (
SELECT
	week_start,
	city_group,
	demand_channel_type,
	demand_channel,
	funnel_first_touchpoint,
	guarantee,
	SUM(visit_booked) AS vb_calculado,
	SUM(visit_completed) AS vc_calculado,
	SUM(offer_submitted) AS os_calculado,
	SUM(offer_accepted) AS oa_calculado,
	SUM(credit_evaluation_init) AS cei_calculado,
	SUM(credit_evaluation_positive) AS cep_calculado,
	SUM(document_sent) AS ds_calculado,
	SUM(credit_approved) AS ca_calculado,
	SUM(contract_signed) AS cs_calculado,
	SUM(new_tenant_prospect) AS ntp_calculado
FROM daily_target_shares
GROUP BY 1, 2, 3, 4, 5, 6
), targets_diff AS (
SELECT
	ct.week_start,
	ct.city_group,
	ct.demand_channel_type,
	ct.demand_channel,
	ct.funnel_first_touchpoint,
	ct.guarantee,
	COALESCE(ct.vb_calculado,0) - COALESCE(pt.vb_congelado,0) AS diff_vb,
	COALESCE(ct.vc_calculado,0) - COALESCE(pt.vc_congelado,0) AS diff_vc,
	COALESCE(ct.os_calculado,0) - COALESCE(pt.os_congelado,0) AS diff_os,
	COALESCE(ct.oa_calculado,0) - COALESCE(pt.oa_congelado,0) AS diff_oa,
	COALESCE(ct.cei_calculado,0) - COALESCE(pt.cei_congelado,0) AS diff_cei,
	COALESCE(ct.cep_calculado,0) - COALESCE(pt.cep_congelado,0) AS diff_cep,
	COALESCE(ct.ds_calculado,0) - COALESCE(pt.ds_congelado,0) AS diff_ds,
	COALESCE(ct.ca_calculado,0) - COALESCE(pt.ca_congelado,0) AS diff_ca,
	COALESCE(ct.cs_calculado,0) - COALESCE(pt.cs_congelado,0) AS diff_cs,
	COALESCE(ct.ntp_calculado,0) - COALESCE(pt.ntp_congelado,0) AS diff_ntp
FROM calculated_targets ct
LEFT JOIN past_targets pt
  ON ct.week_start = pt.week_start
    AND ct.city_group = pt.city_group
	AND ct.demand_channel_type = pt.demand_channel_type
	AND ct.demand_channel = pt.demand_channel
	AND ct.funnel_first_touchpoint = pt.funnel_first_touchpoint
	AND ct.guarantee = pt.guarantee
), calculated_targets_week_month AS (
SELECT
	date,
	week_start,
	city_group,
	demand_channel_type,
	demand_channel,
	funnel_first_touchpoint,
	guarantee,
	visit_booked AS vb_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN visit_booked ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS vb_total_week,
	SUM(visit_completed) AS vc_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN visit_completed ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS vc_total_week,
	SUM(offer_submitted) AS os_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN offer_submitted ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS os_total_week,
	SUM(offer_accepted) AS oa_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN offer_accepted ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS oa_total_week,
	SUM(credit_evaluation_init) AS cei_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN credit_evaluation_init ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS cei_total_week,
	SUM(credit_evaluation_positive) AS cep_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN credit_evaluation_positive ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS cep_total_week,
	SUM(document_sent) AS ds_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN document_sent ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS ds_total_week,
	SUM(credit_approved) AS ca_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN credit_approved ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS ca_total_week,
	SUM(contract_signed) AS cs_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN contract_signed ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS cs_total_week,
	SUM(new_tenant_prospect) AS ntp_calculado,
	SUM(CASE WHEN DATE_TRUNC('month', date) > DATE_TRUNC('month', CURRENT_DATE) THEN new_tenant_prospect ELSE 0 END) OVER(PARTITION BY week_start, city_group, demand_channel_type, demand_channel, funnel_first_touchpoint, guarantee) AS ntp_total_week
FROM daily_target_shares
GROUP BY 1, 2, 3, 4, 5, 6, 7, visit_booked, visit_completed, offer_submitted, offer_accepted, credit_evaluation_init, credit_evaluation_positive, document_sent, credit_approved, contract_signed, new_tenant_prospect
), daily_target_shares_adjusted AS (
SELECT DISTINCT
	COALESCE(g.date, d.date) AS date,
	COALESCE(g.week_start, d.week_start) AS week_start,
	COALESCE(g.city_group, d.city_group) AS city_group,
	COALESCE(g.demand_channel_type, d.demand_channel_type) AS demand_channel_type,
	COALESCE(g.demand_channel, d.demand_channel) AS demand_channel,
	COALESCE(g.funnel_first_touchpoint, d.funnel_first_touchpoint) AS funnel_first_touchpoint,
	COALESCE(g.guarantee, d.guarantee) AS guarantee,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.visit_booked
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.vb_total_week != 0 AND td.diff_vb != 0 THEN td.diff_vb * COALESCE(wm.vb_calculado,0)/wm.vb_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.vb_total_week = 0 AND td.diff_vb != 0 THEN td.diff_vb
		 ELSE d.visit_booked END AS visit_booked,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.visit_completed
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.vc_total_week != 0 AND td.diff_vc != 0 THEN td.diff_vc * COALESCE(wm.vc_calculado,0)/wm.vc_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.vc_total_week = 0 AND td.diff_vc != 0 THEN td.diff_vc
		 ELSE d.visit_completed END AS visit_completed,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.offer_submitted
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.os_total_week != 0 AND td.diff_os != 0 THEN td.diff_os * COALESCE(wm.os_calculado,0)/wm.os_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.os_total_week = 0 AND td.diff_os != 0 THEN td.diff_os
		 ELSE d.offer_submitted END AS offer_submitted,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.offer_accepted
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.oa_total_week != 0 AND td.diff_oa != 0 THEN td.diff_oa * COALESCE(wm.oa_calculado,0)/wm.oa_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.oa_total_week = 0 AND td.diff_oa != 0 THEN td.diff_oa
		 ELSE d.offer_accepted END AS offer_accepted,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.credit_evaluation_init
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.cei_total_week != 0 AND td.diff_cei != 0 THEN td.diff_cei * COALESCE(wm.cei_calculado,0)/wm.cei_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.cei_total_week = 0 AND td.diff_cei != 0 THEN td.diff_cei
		 ELSE d.credit_evaluation_init END AS credit_evaluation_init,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.credit_evaluation_positive
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.cep_total_week != 0 AND td.diff_cep != 0 THEN td.diff_cep * COALESCE(wm.cep_calculado,0)/wm.cep_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.cep_total_week = 0 AND td.diff_cep != 0 THEN td.diff_cep
		 ELSE d.credit_evaluation_positive END AS credit_evaluation_positive,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.document_sent
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.ds_total_week != 0 AND td.diff_ds != 0 THEN td.diff_ds * COALESCE(wm.ds_calculado,0)/wm.ds_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.ds_total_week = 0 AND td.diff_ds != 0 THEN td.diff_ds
		 ELSE d.document_sent END AS document_sent,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.credit_approved
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.ca_total_week != 0 AND td.diff_ca != 0 THEN td.diff_ca * COALESCE(wm.ca_calculado,0)/wm.ca_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.ca_total_week = 0 AND td.diff_ca != 0 THEN td.diff_ca
		 ELSE d.credit_approved END AS credit_approved,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.contract_signed
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.cs_total_week != 0 AND td.diff_cs != 0 THEN td.diff_cs * COALESCE(wm.cs_calculado,0)/wm.cs_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.cs_total_week = 0 AND td.diff_cs != 0 THEN td.diff_cs
		 ELSE d.contract_signed END AS contract_signed,
	CASE 
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) <= DATE_TRUNC('month', CURRENT_DATE) THEN g.new_tenant_prospect
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.ntp_total_week != 0 AND td.diff_ntp != 0 THEN td.diff_ntp * COALESCE(wm.ntp_calculado,0)/wm.ntp_total_week::FLOAT
		WHEN DATE_TRUNC('month', COALESCE(g.date, d.date)) > DATE_TRUNC('month', CURRENT_DATE) AND wm.ntp_total_week = 0 AND td.diff_ntp != 0 THEN td.diff_ntp
		 ELSE d.new_tenant_prospect END AS new_tenant_prospect
FROM daily_target_shares d
FULL OUTER JOIN gsheets_demand_target_adjusted g
  ON d.date = g.date
	AND d.week_start = g.week_start
	AND d.city_group = g.city_group
	AND d.demand_channel_type = g.demand_channel_type
	AND d.demand_channel = g.demand_channel
	AND d.funnel_first_touchpoint = g.funnel_first_touchpoint
	AND d.guarantee = g.guarantee
LEFT JOIN targets_diff td
  ON td.week_start = d.week_start
    AND d.city_group = td.city_group
	AND d.demand_channel_type = td.demand_channel_type
	AND d.demand_channel = td.demand_channel
	AND d.funnel_first_touchpoint = td.funnel_first_touchpoint
	AND d.guarantee = td.guarantee
LEFT JOIN calculated_targets_week_month wm
  ON wm.date = d.date
    AND wm.week_start = d.week_start
    AND wm.city_group = d.city_group
    AND wm.demand_channel_type = d.demand_channel_type
    AND wm.demand_channel = d.demand_channel
    AND wm.funnel_first_touchpoint = d.funnel_first_touchpoint
    AND wm.guarantee = d.guarantee
), negative_targets AS (
SELECT
	date,
	demand_channel_type,
	SUM(CASE WHEN visit_booked < 0 THEN visit_booked END) AS vb_negative,
	SUM(CASE WHEN visit_completed < 0 THEN visit_completed END) AS vc_negative,
	SUM(CASE WHEN offer_submitted < 0 THEN offer_submitted END) AS os_negative,
	SUM(CASE WHEN offer_accepted < 0 THEN offer_accepted END) AS oa_negative,
	SUM(CASE WHEN credit_evaluation_init < 0 THEN credit_evaluation_init END) AS cei_negative,
	SUM(CASE WHEN credit_evaluation_positive < 0 THEN credit_evaluation_positive END) AS cep_negative,
	SUM(CASE WHEN document_sent < 0 THEN document_sent END) AS ds_negative,
	SUM(CASE WHEN credit_approved < 0 THEN credit_approved END) AS ca_negative,
	SUM(CASE WHEN contract_signed < 0 THEN contract_signed END) AS cs_negative,
	SUM(CASE WHEN new_tenant_prospect < 0 THEN new_tenant_prospect END) AS ntp_negative
FROM daily_target_shares_adjusted
GROUP BY 1, 2
)
SELECT
	dt.date,
	dt.week_start,
	dt.city_group,
	dt.demand_channel_type,
	dt.demand_channel,
	dt.funnel_first_touchpoint,
	dt.guarantee,
	CASE WHEN visit_booked <= 0 THEN 0 ELSE visit_booked + (COALESCE(nt.vb_negative,0) * visit_booked/(SUM(CASE WHEN visit_booked > 0 THEN visit_booked END) OVER(PARTITION BY dt.date, dt.demand_channel_type))) END AS visit_booked,
	CASE WHEN visit_completed <= 0 THEN 0 ELSE visit_completed + COALESCE(nt.vc_negative,0) * visit_completed/(SUM(CASE WHEN visit_completed > 0 THEN visit_completed END) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS visit_completed,
	CASE WHEN offer_submitted <= 0 THEN 0 ELSE offer_submitted + COALESCE(nt.os_negative,0) * offer_submitted/(SUM(CASE WHEN offer_submitted > 0 THEN offer_submitted END) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS offer_submitted,
	CASE WHEN offer_accepted <= 0 THEN 0 ELSE offer_accepted + COALESCE(nt.oa_negative,0) * offer_accepted/(SUM(CASE WHEN offer_accepted > 0 THEN offer_accepted END) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS offer_accepted,
	CASE WHEN credit_evaluation_init <= 0 THEN 0 ELSE credit_evaluation_init + COALESCE(nt.cei_negative,0) * credit_evaluation_init/(SUM(CASE WHEN credit_evaluation_init > 0 THEN credit_evaluation_init END) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS credit_evaluation_init,
	CASE WHEN credit_evaluation_positive <= 0 THEN 0 ELSE credit_evaluation_positive + COALESCE(nt.cep_negative,0) * credit_evaluation_positive/(SUM(CASE WHEN credit_evaluation_positive > 0 THEN credit_evaluation_positive END ) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS credit_evaluation_positive,
	CASE WHEN document_sent <= 0 THEN 0 ELSE document_sent + COALESCE(nt.ds_negative,0) * document_sent/(SUM(CASE WHEN document_sent > 0 THEN document_sent END) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS document_sent,
	CASE WHEN credit_approved <= 0 THEN 0 ELSE credit_approved + COALESCE(nt.ca_negative,0) * credit_approved/(SUM(CASE WHEN credit_approved > 0 THEN credit_approved END ) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS credit_approved,
	CASE WHEN contract_signed <= 0 THEN 0 ELSE contract_signed + COALESCE(nt.cs_negative,0) * contract_signed/(SUM(CASE WHEN contract_signed > 0 THEN contract_signed END ) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS contract_signed,
	CASE WHEN new_tenant_prospect <= 0 THEN 0 ELSE new_tenant_prospect + COALESCE(nt.ntp_negative,0) * new_tenant_prospect/(SUM(CASE WHEN new_tenant_prospect > 0 THEN new_tenant_prospect END) OVER(PARTITION BY dt.date, dt.demand_channel_type)) END AS new_tenant_prospect
FROM daily_target_shares_adjusted dt
LEFT JOIN negative_targets nt
  ON dt.date = nt.date
    AND dt.demand_channel_type = nt.demand_channel_type;