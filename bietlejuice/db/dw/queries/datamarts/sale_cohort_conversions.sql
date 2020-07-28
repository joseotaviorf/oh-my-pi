WITH
sale_listing_flows_adjust AS (
SELECT
	sk_lead_date,
	sk_lead,
	sk_prospect_date,
	sk_qualified_date,
	sk_opportunity_date,
	sk_first_listing_date,
	sk_house_listing,
	mkt_origin,
	mkt_channel,
	CASE WHEN mkt_origin = 'B2B' THEN mkt_origin
	     WHEN mkt_completion = 'Full Self-Service' THEN 'FSS'
	     ELSE 'IS'
	END AS lead_context,
	CASE WHEN mkt_campaign_context = 'Organic' THEN 'Branded'
         ELSE mkt_campaign_context
	END AS mkt_campaign_context,
	CASE WHEN mkt_channel IN ('CRM/Notification','Backend','Branding','Other') THEN 'Paid'
         ELSE 'Non Paid'
	END AS mkt_type
FROM datamarts.temp_sale_supply_funnel
),
monday_adjusted AS (
-- treat data from Monday gsheets
SELECT
	NULLIF(mo.name,'') AS id_offer,
	mo.id_buyer||'_'||mo.id_imovel AS sale_flow,
	NULLIF(mo.id_imovel, '')::BIGINT AS id_house,
	NULLIF(mo.id_buyer, '')::BIGINT AS id_user,
	TO_DATE(SUBSTRING(NULLIF(mo.data_proposta, ''),1,10), 'yyyy-mm-dd') AS dt_offer_sent,
	TO_DATE(SUBSTRING(NULLIF(mo.data_aceite_proposta, ''),1,10), 'yyyy-mm-dd') AS dt_offer_accepted,
	TO_DATE(SUBSTRING(NULLIF(mo.data_assinatura_ccv, ''),1,10), 'yyyy-mm-dd') AS dt_ccv_signed,
	TO_DATE(SUBSTRING(NULLIF(mo.data_descarte, ''),1,10), 'yyyy-mm-dd') AS dt_offer_rejected,
	motivo_descarte_pre AS offer_rejection_reason,
	motivo_descarte_pos AS offer_accepted_drop_reason,
	NULLIF(mo.valor_anuncio,'')::FLOAT AS sale_listing_price,
	NULLIF(mo.proposta_buyer,'')::FLOAT AS buyer_offer_price,
	(NULLIF(mo.valor_anuncio,'')::FLOAT - NULLIF(mo.proposta_buyer,'')::FLOAT)/NULLIF(mo.valor_anuncio,'')::FLOAT AS offer_discount
FROM datalake_raw.gsheets_sale_offers_monday mo
),
sale_bookings AS (
SELECT
	db.id_property,
	db.id_visitor,
	db.sk_booking,
	db.dt_created,
	CASE WHEN db.status = 'Realizado' and db.visit_follow_up = 'VaiNegociar' THEN db.dt_scheduling END AS dt_completed
FROM dim_booking db
WHERE db.visit_intent = 'SALE'
  AND db.type = 'Visita'
),
sale_demand_events AS (
SELECT
	COALESCE(offers.id_user, db.id_visitor) AS id_buyer,
	COALESCE(offers.id_house, db.id_property) AS id_house,
	offers.dt_offer_sent,
	offers.dt_offer_accepted,
	offers.dt_ccv_signed,
	offers.id_offer,
	db.sk_booking,
	db.dt_created,
	db.dt_completed
FROM monday_adjusted offers
FULL OUTER JOIN sale_bookings db
  ON (offers.id_house = db.id_property AND offers.id_user = db.id_visitor)
),
sale_demand_classification AS (
SELECT
	sde.id_buyer,
	sde.id_house,
	sde.dt_offer_sent,
	sde.dt_offer_accepted,
	sde.dt_ccv_signed,
	sde.id_offer,
	sde.sk_booking,
	sde.dt_created,
	sde.dt_completed,
	dsf.first_event AS first_touchpoint,
	dsf.higher_intent_before_offer,
	dsf.higher_intent_after_offer
FROM sale_demand_events sde
LEFT JOIN datamarts.demand_sale_flows dsf
  ON sde.id_buyer = dsf.id_buyer
  AND sde.id_house = dsf.id_house
),
p2q AS (
SELECT
	slf.sk_prospect_date AS date_,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
    slf.mkt_type,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) < 5
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1))))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) >= 5
	     	  THEN 'W5+'
	END AS weeks_conversion,
    COUNT(slf.sk_prospect_date) AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10
),
q2o AS (
SELECT
	slf.sk_qualified_date AS date_,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
    slf.mkt_type,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1)))) < 5
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1))))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1)))) >= 5
	     	  THEN 'W5+'
	END AS weeks_conversion,
    NULL::BIGINT AS p2q,
	COUNT(slf.sk_qualified_date) AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10
),
o2fl AS (
SELECT
	slf.sk_opportunity_date AS date_,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
    slf.mkt_type,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1)))) < 5
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1))))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1)))) >= 5
	     	  THEN 'W5+'
	END AS weeks_conversion,
    NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	COUNT(slf.sk_opportunity_date) AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_opportunity_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10
),
vb2vc AS (
SELECT
	REPLACE(DATE(dt_created),'-','')::INTEGER AS date_,
    NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
    NULL AS mkt_type,
    first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed))) < 5
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed))) >= 5
	     	  THEN 'W5+'
	END AS weeks_conversion,
    NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	COUNT(DISTINCT sk_booking) AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9,10
),
vc2os AS (
SELECT
	REPLACE(DATE(dt_completed),'-','')::INTEGER AS date_,
    NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
    NULL AS mkt_type,
    first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent))) < 5
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent))) >= 5
	     	  THEN 'W5+'
	END AS weeks_conversion,
    NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	COUNT(DISTINCT sk_booking) AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9,10
),
vb2os AS (
SELECT
	REPLACE(DATE(dt_created),'-','')::INTEGER AS date_,
    NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
    NULL AS mkt_type,
    first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent))) < 5
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent))) >= 5
	     	  THEN 'W5+'
	END AS weeks_conversion,
    NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	COUNT(DISTINCT sk_booking) AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9,10
),
os2oa AS (
SELECT
	REPLACE(DATE(dt_offer_sent),'-','')::INTEGER AS date_,
    NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
    NULL AS mkt_type,
    first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted))) < 5
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted))) >= 5
	     	  THEN 'W5+'
	END AS weeks_conversion,
    NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	COUNT(DISTINCT id_offer) AS os2oa,
	NULL::BIGINT AS oa2ccv
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9,10
),
oa2ccv AS (
SELECT
	REPLACE(DATE(dt_offer_accepted),'-','')::INTEGER AS date_,
    NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
    NULL AS mkt_type,
    first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed))) < 5
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed))) >= 5
	     	  THEN 'W5+'
	END AS weeks_conversion,
    NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	COUNT(DISTINCT id_offer) AS oa2ccv
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9,10
),
union_all AS (
  SELECT * FROM p2q
	UNION ALL
	SELECT * FROM q2o
	UNION ALL
	SELECT * FROM o2fl
	UNION ALL
	SELECT * FROM vb2vc
	UNION ALL
	SELECT * FROM vc2os
	UNION ALL
	SELECT * FROM vb2os
	UNION ALL
	SELECT * FROM os2oa
	UNION ALL
	SELECT * FROM oa2ccv
),
union_all_date AS (
SELECT
	dd.week_start,
	dd.date,
	dd.month,
	dd.quarter,
	ua.lead_context,
	ua.mkt_campaign_context,
	ua.mkt_origin,
	ua.mkt_channel,
	ua.mkt_type,
	ua.first_origin_demand,
	ua.origin_before_offer,
	ua.origin_after_offer,
	ua.weeks_conversion,
	ua.p2q,
	ua.q2o,
	ua.o2fl,
	ua.vb2vc,
	ua.vc2os,
	ua.vb2os,
	ua.os2oa,
	ua.oa2ccv
FROM union_all ua
RIGHT JOIN dim_date dd
  ON ua.date_ = dd.sk_date
WHERE dd.date BETWEEN '2020-01-01' AND current_date
)
SELECT
	week_start,
	date,
	month,
	quarter,
	lead_context,
	mkt_campaign_context,
	mkt_origin,
	mkt_channel,
	mkt_type,
	first_origin_demand,
	origin_before_offer,
	origin_after_offer,
	weeks_conversion,
	SUM(p2q) AS p2q,
    SUM(q2o) AS q2o,
	SUM(o2fl) AS o2fl,
	SUM(vb2vc) AS vb2vc,
	SUM(vc2os) AS vc2os,
	SUM(vb2os) AS vb2os,
	SUM(os2oa) AS os2oa,
	sum(oa2ccv) AS oa2ccv,
	current_timestamp AS ts_load
FROM union_all_date
GROUP BY week_start,
	 date,
	 month,
	 quarter,
	 lead_context,
	 mkt_campaign_context,
	 mkt_origin,
	 mkt_channel,
	 mkt_type,
	 first_origin_demand,
	 origin_before_offer,
	 origin_after_offer,
	 weeks_conversion;
