WITH
lead_ AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL::BOOLEAN AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
  	COUNT(fhlf.sk_lead_date) AS leads,
	NULL::BIGINT AS prospects, -- this count IS done ON the prospect date because not all listings come FROM a lead, AND maybe one lead brings multiple house listings
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
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS doc_completed,
  	NULL::BIGINT AS credit_processed,
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
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 year ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
prospect AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL::BOOLEAN AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
  	NULL::BIGINT AS leads,
	COUNT(fhlf.sk_prospect_date) AS prospects, -- this count IS done ON the prospect date because not all listings come FROM a lead, AND maybe one lead brings multiple house listings
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
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS doc_completed,
  	NULL::BIGINT AS credit_processed,
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
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 year ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
qualified AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL::BOOLEAN AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
  	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	COUNT(fhlf.sk_qualified_date) AS qualifieds, -- this count IS done ON the qualified date because not all listings come FROM a lead, AND maybe one lead brings multiple house listings
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
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS doc_completed,
  	NULL::BIGINT AS credit_processed,
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
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 year ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
opportunity AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL::BOOLEAN AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
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
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS doc_completed,
  	NULL::BIGINT AS credit_processed,
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
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
listing AS (
SELECT
	dd."date",
	dd.sk_date,
	dr.city_group,
	NULL::BOOLEAN AS is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' THEN fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null AS demand_mkt_channel,
	null AS demand_mkt_medium,
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
  	NULL::BIGINT AS doc_sent,
  	NULL::BIGINT AS doc_approved,
  	NULL::BIGINT AS doc_completed,
  	NULL::BIGINT AS credit_processed,
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
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
messages_sent AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  'Other' AS demand_mkt_channel,
  'Other' AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
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
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
agent_supports AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  'Other' AS demand_mkt_channel,
  'Other' AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
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
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
visits_booked AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  db.mkt_channel AS demand_mkt_channel,
  db.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_booking_created_date
  AND rf.sk_booking_created_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_booking db
  ON rf.sk_booking = db.sk_booking
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
visits_completed AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  db.mkt_channel AS demand_mkt_channel,
  db.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_visit_date
  AND rf.sk_visit_date > 0 AND rf.flg_visit_completed = 1
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_booking db
  ON rf.sk_booking = db.sk_booking
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
offer_submitted AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_offer_submitted_date
  AND rf.sk_offer_submitted_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date"between DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
offer_approved AS(
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_offer_approved_date
  AND rf.sk_offer_approved_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
credit_evaluation_init AS(
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_first_credit_evaluation_init
  AND rf.sk_first_credit_evaluation_init > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
credit_evaluation_positive AS(
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_first_credit_evaluation_positive
  AND rf.sk_first_credit_evaluation_positive > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
doc_sent AS(
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  COUNT(DISTINCT rf.sk_offer) AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_tenant_first_doc_sent_date
  AND rf.sk_tenant_first_doc_sent_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
doc_approved AS(
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  COUNT(DISTINCT rf.sk_offer) AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_last_doc_analysis_approved
  AND rf.sk_last_doc_analysis_approved > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
doc_completed AS(
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  COUNT(DISTINCT rf.sk_offer) AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_credit_analysis_init_date
  AND rf.sk_credit_analysis_init_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
credit_processed AS(
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  COUNT(DISTINCT rf.sk_offer) AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_credit_analysis_end_date
  AND rf.sk_credit_analysis_end_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
credit_approved AS(
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  COUNT(DISTINCT rf.sk_offer) AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_credit_analysis_approved_date
  AND rf.sk_credit_analysis_approved_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
contract_created AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  COUNT(DISTINCT rf.sk_contract) AS contract_created,
  NULL::BIGINT AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_contract_created_date
  AND rf.sk_contract_created_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
contract_signed AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  COUNT(DISTINCT rf.sk_contract) AS contract_signed,
  NULL::BIGINT  AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_contract_signed_date
  AND rf.sk_contract_signed_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
contract_ended AS (
SELECT
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  NULL AS supply_mkt_origin,
  NULL AS supply_mkt_channel,
  NULL AS lead_context,
  dof.mkt_channel AS demand_mkt_channel,
  dof.mkt_medium AS demand_mkt_medium,
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
  NULL::BIGINT AS doc_sent,
  NULL::BIGINT AS doc_approved,
  NULL::BIGINT AS doc_completed,
  NULL::BIGINT AS credit_processed,
  NULL::BIGINT AS credit_approved,
  NULL::BIGINT AS contract_created,
  NULL::BIGINT AS contract_signed,
  COUNT(DISTINCT rf.sk_contract) AS contract_ended
FROM dim_date dd
JOIN fact_listing_rent_flows rf
  ON dd.sk_date = rf.sk_contract_annulment_date
  AND rf.sk_contract_signed_date > 0 AND rf.sk_contract_annulment_date > 0
JOIN dim_house_listing dhl
  ON rf.sk_house_listing = dhl.sk_house_listing
LEFT JOIN dim_offer dof
  ON rf.sk_offer = dof.sk_offer
LEFT JOIN dim_region dr
  ON rf.sk_region = dr.sk_region
WHERE dd."date" BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE -- filter data FROM 4 years ago
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
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
	SELECT * FROM doc_sent
	UNION ALL
	SELECT * FROM doc_approved
	UNION ALL
	SELECT * FROM doc_completed
	UNION ALL
	SELECT * FROM credit_processed
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
  ua.doc_sent,
  ua.doc_approved,
  ua.doc_completed,
  ua.credit_processed,
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
  is_b2b AS is_b2b_demand,
  SUM(leads) AS leads,
  SUM(prospects) AS prospects,
  SUM(qualifieds) AS qualifieds,
  SUM(opportunities) AS opportunities,
  SUM(first_listings) AS first_listings,
  SUM(messages_sent_tta) AS messages_sent_tta,
  SUM(registered_agent_supports) AS registered_agent_supports,
  SUM(visits_booked) AS visits_booked,
  SUM(visits_completed) AS visits_completed,
  SUM(offer_submitted) AS offer_submitted,
  SUM(offer_approved) AS offer_approved,
  SUM(COALESCE(credit_evaluation_init,0)) AS credit_evaluation_init,
  SUM(COALESCE(credit_evaluation_positive,0)) AS credit_evaluation_positive,
  SUM(doc_sent) AS doc_sent,
  SUM(COALESCE(doc_approved,0)) AS doc_approved,
  SUM(doc_completed) AS doc_completed,
  SUM(credit_processed) AS credit_processed,
  SUM(credit_approved) AS credit_approved,
  SUM(contract_created) AS contract_created,
  SUM(contract_signed) AS contract_signed,
  SUM(contract_ended) AS contract_ended,
  current_timestamp AS ts_load
FROM union_all
GROUP BY "date", city_group, 3, 4, 5, 6, 7, 8;