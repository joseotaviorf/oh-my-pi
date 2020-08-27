WITH
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
booking AS (
	SELECT
		flrf.sk_client,
		a.id_property AS id_house,
		flrf.sk_region,
		a.mkt_origin,
		a.mkt_channel,
		a.mkt_medium,
		a.mkt_source,
		a.utm_campaign,
		a.utm_term,
		a.utm_content,
		a.dt_created AS ts_event,
		'Booking' AS flow_event
	FROM
		dim_booking a
	join fact_listing_rent_Flows flrf
	using(sk_booking)
	WHERE
		a.sk_booking > 0
		AND a.visit_intent = 'RENT'
		AND a.type = 'Visita'
		AND a.dt_created IS NOT NULL
),
offer AS (
	SELECT
		flrf.sk_client,
		a.id_property AS id_house,
		flrf.sk_region,
		a.mkt_origin,
		a.mkt_channel,
		a.mkt_medium,
		a.mkt_source,
		a.utm_campaign,
		a.utm_term,
		a.utm_content,
		a.dt_first_sent AS ts_event,
		'Offer' AS flow_event
	FROM
		dim_offer AS a
	JOIN fact_listing_rent_flows AS flrf
	USING(sk_offer)
	WHERE
		a.sk_offer > 0
		AND a.dt_first_sent IS NOT NULL
),
talk_to_agent AS (
	SELECT
		tenant_id::INT AS sk_client,
		house_id::INT AS id_house,
		fhl.sk_region,
		a.mkt_origin,
		a.mkt_channel,
		a.mkt_medium,
		a.mkt_source,
		a.utm_campaign,
		a.utm_term,
		a.utm_content,
		a.first_message_ts::timestamp AS ts_event,
		'Talk to Agent' AS flow_event
	FROM
		datamarts.talk_to_agent AS a
	JOIN fact_house_listings AS fhl
		ON a.sk_house_listing = fhl.sk_house_listing
	WHERE
		a.business_context = 'RENT'
		AND a.first_message_ts IS NOT NULL
),
----------------------------------------------------------------------------------------------------------------------
-- Merge activation events (offer, booking and talk to agent) and order them by user and rent_flows (user || house) --
----------------------------------------------------------------------------------------------------------------------
rent_flows_raw AS (
	SELECT
		evt.*,
		DATE(evt.ts_event) AS dt_event,
		dr.city_group,
		evt.sk_client || '_' || evt.id_house as sk_rf,
		ROW_NUMBER() OVER(PARTITION BY evt.sk_client, evt.id_house
							ORDER BY evt.ts_event) AS rent_flow_order,
		ROW_NUMBER() OVER(PARTITION BY evt.sk_client
							ORDER BY evt.ts_event) AS tenant_prospect_order
	FROM (
		SELECT
			b.*
		FROM booking AS b

		UNION ALL

		SELECT
			o.*
		FROM offer AS o

		UNION ALL

		SELECT
			tta.*
		FROM talk_to_agent AS tta
	) AS evt
	JOIN dim_region AS dr
		ON evt.sk_region = dr.sk_region
),
----------------------------------
-- Query the rent bottom funnel --
----------------------------------
rental_funnel AS (
	SELECT DISTINCT
		flrf.sk_client,
		SUBSTRING(flrf.sk_house_listing, 1, 9) AS id_house,
		NULLIF(flrf.sk_booking, -1) AS sk_booking,
		NULLIF(flrf.sk_offer, -1) AS sk_offer,
		NULLIF(flrf.sk_proposal, -1) AS sk_proposal,
		NULLIF(flrf.sk_contract, -1) AS sk_contract,
		dd_bc.date AS dt_booking_created,
		flrf.flg_visit_completed,
		dd_os.date AS dt_offer_submitted,
		dd_oa.date AS dt_offer_approved,
		dd_ds.date AS dt_tenant_first_doc_sent,
		dd_ca.date AS dt_credit_analysis_approved,
		dd_cs.date AS dt_contract_signed
	FROM
		fact_listing_rent_flows AS flrf
	JOIN dim_date AS dd_bc
		ON flrf.sk_booking_created_date = dd_bc.sk_date
	JOIN dim_date AS dd_os
		ON flrf.sk_offer_submitted_date = dd_os.sk_date
	JOIN dim_date AS dd_oa
		ON flrf.sk_offer_approved_date = dd_oa.sk_date
	JOIN dim_date AS dd_ds
		ON flrf.sk_tenant_first_doc_sent_date = dd_ds.sk_date
	JOIN dim_date AS dd_ca
		ON flrf.sk_credit_analysis_approved_date = dd_ca.sk_date
	JOIN dim_date AS dd_cs
		ON flrf.sk_contract_signed_date = dd_cs.sk_date
	WHERE
		COALESCE(dd_bc.date, dd_os.date) > 0
),
------------------------------------------------------------------------------------------
-- Join the rent bottom funnel in the first rent flow cohort and introduce 0s for UNION --
------------------------------------------------------------------------------------------
fact_rent_flows AS (
	SELECT
		rf.dt_event,
		rf.city_group,
		rf.flow_event,
		rf.mkt_origin,
		rf.mkt_channel,
		rf.mkt_medium,
		rf.mkt_source,
		rf.utm_campaign,
		rf.utm_term,
		rf.utm_content,
		''::TEXT AS campaign_name,
		rf.sk_rf,
		rf.sk_client,
		rf.id_house,
		rf.rent_flow_order,
		rf.tenant_prospect_order,
		frf.sk_booking,
		frf.sk_offer,
		frf.sk_proposal,
		frf.sk_contract,
		frf.dt_booking_created,
		frf.flg_visit_completed,
		frf.dt_offer_submitted,
		frf.dt_offer_approved,
		frf.dt_tenant_first_doc_sent,
		frf.dt_credit_analysis_approved,
		frf.dt_contract_signed,
		0.0 AS marketing_cost,
		0.0 AS new_rent_flows_target,
		0.0 AS new_tenant_prospects_target,
		0.0 AS budget
	FROM
		rent_flows_raw AS rf
	LEFT JOIN rental_funnel AS frf
		ON rf.sk_client = frf.sk_client
		AND rf.id_house = frf.id_house
		AND rf.rent_flow_order = 1
),
-------------------------------------------------------------------------------------------------------------------------------
-- Query Performance Marketing Investment for Rental Demand costs (mkt_origin = 'Tenants PWA') and introduce NULLs for UNION --
-------------------------------------------------------------------------------------------------------------------------------
demand_daily_spent AS (
	SELECT
		dd.date AS dt_event,
		co.city_group,
		''::TEXT AS flow_event,
		co.mkt_origin,
		co.mkt_channel,
		co.mkt_medium,
		co.mkt_source,
		''::TEXT AS utm_campaign,
		co.utm_term,
		co.utm_content,
		co.campaign_name,
		NULL AS sk_rf,
		NULL::INT AS sk_client,
		NULL::INT AS id_house,
		NULL::INT AS rent_flow_order,
		NULL::INT AS tenant_prospect_order,
		NULL::INT AS sk_booking,
		NULL::INT AS sk_offer,
		NULL::INT AS sk_proposal,
		NULL::INT AS sk_contract,
		NULL::DATE AS dt_booking_created,
		NULL::BOOL AS flg_visit_completed,
		NULL::DATE AS dt_offer_submitted,
		NULL::DATE AS dt_offer_approved,
		NULL::DATE AS dt_tenant_first_doc_sent,
		NULL::DATE AS dt_credit_analysis_approved,
		NULL::DATE AS dt_contract_signed,
		SUM(co.cost::FLOAT) AS marketing_cost,
		0.0 AS new_rent_flows_target,
		0.0 AS new_tenant_prospects_target,
		0.0 AS budget
	FROM
		marketing.fact_marketing_daily_costs AS co
	JOIN dim_date AS dd
		ON dd.sk_date = co.sk_date
	WHERE
		co.mkt_origin = 'Tenants PWA'
		AND dd.date >= CURRENT_DATE - INTERVAL '12 MONTH'
	GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,29,30,31
),
-------------------------------------------------------------------------------------
-- Query Performance Marketing Rental Demand targets and introduce NULLs for UNION --
-------------------------------------------------------------------------------------
demand_daily_targets AS (
	SELECT
		NULLIF(str.date, '')::date AS dt_event,
		NULLIF(str.city_group, '') AS city_group,
		'' AS flow_event,
		'Tenants PWA' AS mkt_origin,
		NULLIF(str.mkt_channel, '') AS mkt_channel,
		NULLIF(str.mkt_medium, '') AS mkt_medium,
		''::TEXT AS mkt_source,
		''::TEXT AS utm_campaign,
		''::TEXT AS utm_term,
		''::TEXT AS utm_content,
		''::TEXT AS campaign_name,
		NULL AS sk_rf,
		NULL::INT AS sk_client,
		NULL::INT AS id_house,
		NULL::INT AS rent_flow_order,
		NULL::INT AS tenant_prospect_order,
		NULL::INT AS sk_booking,
		NULL::INT AS sk_offer,
		NULL::INT AS sk_proposal,
		NULL::INT AS sk_contract,
		NULL::DATE AS dt_booking_created,
		NULL::BOOL AS flg_visit_completed,
		NULL::DATE AS dt_offer_submitted,
		NULL::DATE AS dt_offer_approved,
		NULL::DATE AS dt_tenant_first_doc_sent,
		NULL::DATE AS dt_credit_analysis_approved,
		NULL::DATE AS dt_contract_signed,
		0.0 AS marketing_cost,
		NULLIF(str.new_rent_flows_target, '')::FLOAT AS new_rent_flows_target,
		NULLIF(str.new_tenant_prospects_target, '')::FLOAT AS new_tenant_prospects_target,
		NULLIF(str.budget, '')::FLOAT AS budget
	FROM
		datalake_raw.gsheets_demand_targets_replanning AS str
	WHERE
		NULLIF(str.date, '')::date >= CURRENT_dATE - INTERVAL '12 MONTH'
)
SELECT
	rf.*
FROM
	fact_rent_flows AS rf

UNION ALL

SELECT
	dds.*
FROM
	demand_daily_spent AS dds

UNION ALL

SELECT
	ddt.*
FROM
	demand_daily_targets AS ddt