WITH
lead_ AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
	NULL AS first_touchpoint,
	FALSE AS is_guarantee,
  	COUNT(fhlf.sk_lead_date) AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS messages_sent_tta,
	NULL::BIGINT AS registered_agent_supports,
	NULL::BIGINT AS visits_booked,
  	NULL::BIGINT AS visits_completed,
  	NULL::BIGINT AS offer_submitted,
  	NULL::BIGINT AS offer_approved,
  	NULL::BIGINT AS credit_evaluation_init,
  	NULL::BIGINT AS credit_evaluation_positive,
  	NULL::BIGINT AS guarantee_started,
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS guarantee_paid,
  	NULL::BIGINT AS credit_approved,
  	NULL::BIGINT AS contract_created,
  	NULL::BIGINT AS contract_signed,
  	NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_house_listing_flows fhlf
  ON dd.sk_date = fhlf.sk_lead_date
  AND fhlf.sk_lead_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = fhlf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
prospect AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
	NULL AS first_touchpoint,
	FALSE AS is_guarantee,
  	NULL::BIGINT AS leads,
	COUNT(fhlf.sk_prospect_date) AS prospects, -- this count is done on the prospect date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS messages_sent_tta,
	NULL::BIGINT AS registered_agent_supports,
	NULL::BIGINT AS visits_booked,
  	NULL::BIGINT AS visits_completed,
  	NULL::BIGINT AS offer_submitted,
  	NULL::BIGINT AS offer_approved,
  	NULL::BIGINT AS credit_evaluation_init,
  	NULL::BIGINT AS credit_evaluation_positive,
  	NULL::BIGINT AS guarantee_started,
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS guarantee_paid,
  	NULL::BIGINT AS credit_approved,
  	NULL::BIGINT AS contract_created,
  	NULL::BIGINT AS contract_signed,
  	NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_house_listing_flows fhlf
  ON dd.sk_date = fhlf.sk_prospect_date
  AND fhlf.sk_prospect_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = fhlf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
qualified AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
	NULL AS first_touchpoint,
	FALSE AS is_guarantee,
  	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	COUNT(fhlf.sk_qualified_date) AS qualifieds, -- this count is done on the qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS messages_sent_tta,
	NULL::BIGINT AS registered_agent_supports,
	NULL::BIGINT AS visits_booked,
  	NULL::BIGINT AS visits_completed,
  	NULL::BIGINT AS offer_submitted,
  	NULL::BIGINT AS offer_approved,
  	NULL::BIGINT AS credit_evaluation_init,
  	NULL::BIGINT AS credit_evaluation_positive,
  	NULL::BIGINT AS guarantee_started,
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS guarantee_paid,
  	NULL::BIGINT AS credit_approved,
  	NULL::BIGINT AS contract_created,
  	NULL::BIGINT AS contract_signed,
  	NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_house_listing_flows fhlf
  ON dd.sk_date = fhlf.sk_qualified_date
  AND fhlf.sk_qualified_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = fhlf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
opportunity AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
	NULL AS first_touchpoint,
	FALSE AS is_guarantee,
  	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	COUNT(DISTINCT fhlf.sk_house_listing) AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS messages_sent_tta,
	NULL::BIGINT AS registered_agent_supports,
	NULL::BIGINT AS visits_booked,
  	NULL::BIGINT AS visits_completed,
  	NULL::BIGINT AS offer_submitted,
  	NULL::BIGINT AS offer_approved,
  	NULL::BIGINT AS credit_evaluation_init,
  	NULL::BIGINT AS credit_evaluation_positive,
  	NULL::BIGINT AS guarantee_started,
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS guarantee_paid,
  	NULL::BIGINT AS credit_approved,
  	NULL::BIGINT AS contract_created,
  	NULL::BIGINT AS contract_signed,
  	NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_house_listing_flows fhlf
  ON dd.sk_date = fhlf.sk_opportunity_date
  AND fhlf.sk_opportunity_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = fhlf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
listing AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' OR fhlf.mkt_origin = 'CIQ' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
	NULL AS first_touchpoint,
	FALSE AS is_guarantee,
  	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	COUNT(fhlf.sk_first_listing_date) AS first_listings,
	NULL::BIGINT AS messages_sent_tta,
	NULL::BIGINT AS registered_agent_supports,
	NULL::BIGINT AS visits_booked,
  	NULL::BIGINT AS visits_completed,
  	NULL::BIGINT AS offer_submitted,
  	NULL::BIGINT AS offer_approved,
  	NULL::BIGINT AS credit_evaluation_init,
  	NULL::BIGINT AS credit_evaluation_positive,
  	NULL::BIGINT AS guarantee_started,
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS guarantee_paid,
  	NULL::BIGINT AS credit_approved,
  	NULL::BIGINT AS contract_created,
  	NULL::BIGINT AS contract_signed,
  	NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_house_listing_flows fhlf
  ON dd.sk_date = fhlf.sk_first_listing_date
  AND fhlf.sk_first_listing_date > 0
LEFT JOIN dim_region dr
  ON dr.sk_region = fhlf.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
messages_sent AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  CASE
    WHEN dhl.is_b2b= TRUE THEN 'B2B'
    WHEN dhl.is_b2b = FALSE THEN 'FALSE'
  END AS is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  'Other' AS demand_mkt_channel,
  'Other' AS demand_mkt_medium,
  NULL AS first_touchpoint,
  FALSE AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  COUNT(DISTINCT (tta.agent_id || tta.tenant_id || tta.sk_house_listing)) AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN datamarts.talk_to_agent tta
  ON date(tta.first_message_ts) = dd.date
JOIN dim_house_listing dhl
  ON tta.sk_house_listing = dhl.sk_house_listing
LEFT JOIN (SELECT distinct city_group, region_code FROM dim_region) dr
  ON tta.region_code = dr.region_code
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
agent_supports AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  CASE
    WHEN dhl.is_b2b= TRUE THEN 'B2B'
    WHEN dhl.is_b2b = FALSE THEN 'FALSE'
  END AS is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  'Other' AS demand_mkt_channel,
  'Other' AS demand_mkt_medium,
  NULL AS first_touchpoint,
  FALSE AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  COUNT(DISTINCT (tta.agent_id || tta.tenant_id || tta.sk_house_listing)) AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN datamarts.talk_to_agent tta
  ON date(tta.first_attendance_ts) = dd.date
JOIN fact_listing_rent_flows rf
  ON tta.sk_house_listing = rf.sk_house_listing
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
rent_flow_adjusted AS (
SELECT
    rf.sk_rent_flow,
    rf.sk_house_listing,
    rf.sk_client,
    rf.sk_region,
    rf.sk_visit_date,
    rf.flg_visit_completed,
    rf.sk_proposal,
    rf.sk_contract_annulment_date,
    rf.sk_booking,
    rf.sk_booking_created_date,
    rf.sk_offer,
    rf.sk_offer_submitted_date,
    rf.sk_offer_approved_date,
    rf.sk_first_credit_evaluation_init,
    rf.sk_first_credit_evaluation_positive,
    rf.sk_guarantee_date,
    rf.sk_tenant_first_doc_sent_date,
    rf.sk_last_doc_analysis_approved,
    rf.sk_credit_analysis_init_date,
    rf.sk_credit_analysis_end_date,
    rf.sk_guarantee_paid_date,
    rf.sk_credit_analysis_approved_date,
    rf.sk_contract,
    rf.sk_contract_created_date,
    rf.sk_contract_signed_date,
    fdf.funnel_flow,
    fdf.funnel_first_touchpoint,
    fdf.had_flow_visit,
    fdf.had_flow_direct,
    fdf.had_flow_tta,
    fdf.flow_type,
    dp.guarantee,
    CASE
        WHEN dhl.is_b2b = TRUE THEN 'B2B'
        WHEN ciq.is_quintoandar_consultant = TRUE THEN 'CIQ'
        WHEN dhl.is_b2b = FALSE OR ciq.is_quintoandar_consultant = FALSE THEN 'FALSE'
    END AS is_b2b,
    dr.city_group,
    db.mkt_channel AS demand_mkt_channel_booking,
    db.mkt_medium AS demand_mkt_medium_booking,
    dof.mkt_channel AS demand_mkt_channel_offer,
    dof.mkt_medium AS demand_mkt_medium_offer
FROM fact_listing_rent_flows rf
LEFT JOIN dim_proposal dp
  ON rf.sk_proposal = dp.sk_proposal
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_booking db
  ON rf.sk_booking = db.sk_booking
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN datamarts.funnel_demand_flows fdf
  ON rf.sk_rent_flow = fdf.sk_rent_flow
LEFT JOIN datamarts.quintoandar_consultant_listings ciq
  ON rf.sk_house_listing = ciq.sk_house_listing
),
visits_booked AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_booking AS demand_mkt_channel,
  rf.demand_mkt_medium_booking AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  FALSE AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  COUNT(DISTINCT rf.sk_booking) AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_booking_created_date
  AND rf.sk_booking_created_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
visits_completed AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_booking AS demand_mkt_channel,
  rf.demand_mkt_medium_booking AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  FALSE AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  COUNT(DISTINCT rf.sk_booking) AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_visit_date
  AND rf.sk_visit_date > 0 AND rf.flg_visit_completed = 1
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
offer_submitted AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_booking AS demand_mkt_channel,
  rf.demand_mkt_medium_booking AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  FALSE AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  COUNT(DISTINCT rf.sk_offer) AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_offer_submitted_date
  AND rf.sk_offer_submitted_date > 0
WHERE dd."date"between DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
offer_approved AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  FALSE AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  COUNT(DISTINCT rf.sk_offer) AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_offer_approved_date
  AND rf.sk_offer_approved_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data from 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_evaluation_init AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  COUNT(DISTINCT rf.sk_offer) AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_first_credit_evaluation_init
  AND rf.sk_first_credit_evaluation_init > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_evaluation_positive AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  COUNT(DISTINCT rf.sk_offer) AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_first_credit_evaluation_positive
  AND rf.sk_first_credit_evaluation_positive > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
guarantee_started AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  COUNT(DISTINCT rf.sk_offer) AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_guarantee_date
  AND rf.sk_guarantee_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
doc_sent AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  COUNT(DISTINCT rf.sk_offer) AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_tenant_first_doc_sent_date
  AND rf.sk_tenant_first_doc_sent_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
doc_approved AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  COUNT(DISTINCT rf.sk_offer) AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_last_doc_analysis_approved
  AND rf.sk_last_doc_analysis_approved > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
guarantee_paid AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  COUNT(DISTINCT rf.sk_offer) AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_guarantee_paid_date
  AND rf.sk_guarantee_paid_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_approved AS(
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  COUNT(DISTINCT rf.sk_offer) AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_credit_analysis_approved_date
  AND rf.sk_credit_analysis_approved_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_created AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  COUNT(DISTINCT rf.sk_contract) AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_contract_created_date
  AND rf.sk_contract_created_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_signed AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  COUNT(DISTINCT rf.sk_contract) AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_contract_signed_date
  AND rf.sk_contract_signed_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_ended AS (
SELECT
  dd."date",
  dd.sk_date,
  rf.city_group,
  rf.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  rf.demand_mkt_channel_offer AS demand_mkt_channel,
  rf.demand_mkt_medium_offer AS demand_mkt_medium,
  rf.funnel_first_touchpoint AS first_touchpoint,
  rf.guarantee = 'RentalGuarantee' AS is_guarantee,
  NULL::BIGINT AS leads,
  NULL::BIGINT AS prospects,
  NULL::BIGINT AS qualifieds,
  NULL::BIGINT AS opportunities,
  NULL::BIGINT AS first_listings,
  NULL::BIGINT AS messages_sent_tta,
  NULL::BIGINT AS registered_agent_supports,
  NULL::BIGINT AS visits_booked,
  NULL::BIGINT AS visits_completed,
  NULL::BIGINT AS offer_submitted,
  NULL::BIGINT AS offer_approved,
  NULL::BIGINT AS credit_evaluation_init,
  NULL::BIGINT AS credit_evaluation_positive,
  NULL::BIGINT AS guarantee_started,
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS guarantee_paid,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  COUNT(DISTINCT rf.sk_contract) AS contract_ended
FROM dim_date dd
JOIN rent_flow_adjusted rf
  ON dd.sk_date = rf.sk_contract_annulment_date
  AND rf.sk_contract_signed_date > 0 AND rf.sk_contract_annulment_date > 0
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
union_all AS (
  SELECT * FROM lead_
	UNION ALL
	SELECT * FROM prospect
	UNION ALL
	SELECT * FROM qualified
	UNION ALL
	SELECT * FROM opportunity
	UNION ALL
	SELECT * FROM listing
	UNION ALL
	SELECT * FROM messages_sent
	UNION ALL
	SELECT * FROM agent_supports
	UNION ALL
	SELECT * FROM visits_booked
	UNION ALL
	SELECT * FROM visits_completed
	UNION ALL
	SELECT * FROM offer_submitted
	UNION ALL
	SELECT * FROM offer_approved
	UNION ALL
	SELECT * FROM credit_evaluation_init
	UNION ALL
	SELECT * FROM credit_evaluation_positive
	UNION ALL
	SELECT * FROM guarantee_started
	UNION ALL
	SELECT * FROM doc_sent
	UNION ALL
	SELECT * FROM doc_approved
	UNION ALL
	SELECT * FROM guarantee_paid
	UNION ALL
	SELECT * FROM credit_approved
	UNION ALL
	SELECT * FROM contract_created
	UNION ALL
	SELECT * FROM contract_signed
	UNION ALL
	SELECT * FROM contract_ended
),
union_all_date AS (
SELECT
  dd."date",
  ua.city_group,
  ua.is_b2b,
  ua.supply_mkt_origin,
  ua.supply_mkt_channel,
  ua.lead_context,
  ua.demand_mkt_channel,
  ua.demand_mkt_medium,
  ua.first_touchpoint,
  ua.is_guarantee,
  ua.leads,
  ua.prospects,
  ua.qualifieds,
  ua.opportunities,
  ua.first_listings,
  ua.messages_sent_tta,
  ua.registered_agent_supports,
  ua.visits_booked,
  ua.visits_completed,
  ua.offer_submitted,
  ua.offer_approved,
  ua.credit_evaluation_init,
  ua.credit_evaluation_positive,
  ua.guarantee_started,
  ua.doc_sent,
  ua.doc_approved,
  ua.guarantee_paid,
  ua.credit_approved,
  ua.contract_created,
  ua.contract_signed,
  ua.contract_ended
FROM union_all ua
RIGHT JOIN dim_date dd
  ON ua.sk_date = dd.sk_date
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE
)
SELECT
	"date",
	city_group,
	supply_mkt_origin,
  	CASE WHEN supply_mkt_origin = 'Owner PWA' THEN supply_mkt_channel
  	   when supply_mkt_origin != 'Owner PWA' THEN supply_mkt_origin
  	   END AS supply_mkt_origin_detailed,
  	lead_context,
    CASE WHEN demand_mkt_channel in ('Not Mapped', 'Other') or demand_mkt_channel IS NULL THEN 'Other'
         ELSE demand_mkt_channel END AS demand_mkt_channel,
    case when demand_mkt_channel in ('Not Mapped', 'Other') or demand_mkt_channel is null then 'Other'
	     when demand_mkt_channel in ('Online Classifieds','Agents') then demand_mkt_channel
	     when demand_mkt_medium in ('SEO branded', 'SEO non-branded') then 'SEO'
	     else demand_mkt_medium
	end as demand_mkt_channel_detailed,
	first_touchpoint,
	is_guarantee,
    is_b2b AS is_b2b_demand,
    SUM(COALESCE(leads,0)) AS leads,
    SUM(COALESCE(prospects,0)) AS prospects,
    SUM(COALESCE(qualifieds,0)) AS qualifieds,
    SUM(COALESCE(opportunities,0)) AS opportunities,
    SUM(COALESCE(first_listings,0)) AS first_listings,
    SUM(COALESCE(messages_sent_tta,0)) AS messages_sent_tta,
    SUM(COALESCE(registered_agent_supports,0)) AS registered_agent_supports,
    SUM(COALESCE(visits_booked,0)) AS visits_booked,
    SUM(COALESCE(visits_completed,0)) AS visits_completed,
    SUM(COALESCE(offer_submitted,0)) AS offer_submitted,
    SUM(COALESCE(offer_approved,0)) AS offer_approved,
    SUM(COALESCE(credit_evaluation_init,0)) AS credit_evaluation_init,
    SUM(COALESCE(credit_evaluation_positive,0)) AS credit_evaluation_positive,
    SUM(COALESCE(guarantee_started,0)) AS guarantee_started,
    SUM(COALESCE(doc_sent,0)) AS doc_sent,
    SUM(COALESCE(doc_approved,0)) AS doc_approved,
    SUM(COALESCE(guarantee_paid,0)) AS guarantee_paid,
    SUM(COALESCE(credit_approved,0)) AS credit_approved,
    SUM(COALESCE(contract_created,0)) AS contract_created,
    SUM(COALESCE(contract_signed,0)) AS contract_signed,
    SUM(COALESCE(contract_ended,0)) AS contract_ended,
    current_timestamp AS ts_load
FROM union_all
GROUP BY "date", city_group, 3, 4, 5, 6, 7, 8, 9, 10