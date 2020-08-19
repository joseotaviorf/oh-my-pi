WITH
sale_listing_flows_adjust AS (
SELECT
	lf.sk_lead_date,
	lf.sk_lead,
	lf.sk_prospect_date,
	lf.sk_first_contact_date,
	lf.sk_qualified_date,
	lf.sk_opportunity_date,
	lf.sk_first_listing_date,
	lf.sk_house_listing,
	lf.mkt_origin,
	lf.mkt_channel,
	CASE WHEN lf.mkt_origin = 'B2B' THEN mkt_origin
	     WHEN lf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	     ELSE 'IS'
	END AS lead_context,
	CASE WHEN lf.lead_context_origin = 'Organic' THEN 'Branded'
         ELSE lead_context_origin
	END AS mkt_campaign_context,
	CASE WHEN lf.mkt_channel IN ('CRM/Notification','Backend','Branding','Other') THEN 'Paid'
         ELSE 'Non Paid'
	END AS mkt_type,
	CASE WHEN dr.city_group NOT IN ('RMSP', 'Rio de Janeiro') THEN NULL ELSE dr.city_group END AS city_group
FROM sale.fact_listing_flows lf
LEFT JOIN dim_region dr
  ON dr.sk_region = lf.sk_region
),
monday_adjusted AS (
-- treat data from Monday gsheets
SELECT
	NULLIF(mo.name,'') AS id_offer,
	mo.id_buyer||'_'||mo.id_imovel AS sale_flow,
	NULLIF(mo.id_imovel, '')::BIGINT AS id_house,
	NULLIF(mo.id_buyer, '')::BIGINT AS id_user,
	CASE WHEN forma_pagamento IN ('À vista + FGTS', 'À vista') THEN 'À vista'
		 WHEN forma_pagamento IN ('Financiado', 'Financiado por fora', 'À vista, Financiado') THEN 'Financiado'
		 ELSE forma_pagamento
	END AS form_of_payment,
	TO_DATE(SUBSTRING(NULLIF(mo.data_proposta, ''),1,10), 'yyyy-mm-dd') AS dt_offer_sent,
	TO_DATE(SUBSTRING(NULLIF(mo.data_aceite_proposta, ''),1,10), 'yyyy-mm-dd') AS dt_offer_accepted,
	TO_DATE(SUBSTRING(NULLIF(mo.data_assinatura_ccv, ''),1,10), 'yyyy-mm-dd') AS dt_ccv_signed,
	TO_DATE(SUBSTRING(NULLIF(mo.data_descarte, ''),1,10), 'yyyy-mm-dd') AS dt_offer_rejected,
	TO_DATE(SUBSTRING(NULLIF(mo.diligencia_inicio, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_started,
	TO_DATE(SUBSTRING(NULLIF(mo.diligencia_retorno_buyer_seller, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_approved,
	TO_DATE(SUBSTRING(NULLIF(mo.credito_inicio, ''),1,10), 'yyyy-mm-dd') AS dt_credit_started,
	TO_DATE(SUBSTRING(NULLIF(mo.credito_fim, ''),1,10), 'yyyy-mm-dd') AS dt_credit_approved,
	TO_DATE(SUBSTRING(NULLIF(mo.data_pagto_seller, ''),1,10), 'yyyy-mm-dd') AS dt_payment_concluded,
	TO_DATE(SUBSTRING(NULLIF(mo.cri_fim, ''),1,10), 'yyyy-mm-dd') AS dt_matricula_atualizada,
	TO_DATE(SUBSTRING(NULLIF(mo.data_chaves_buyer, ''),1,10), 'yyyy-mm-dd') AS dt_entrega_chaves,
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
sale_demand_region AS (
SELECT
	dsf.id_house,
	dr.city_group
FROM datamarts.demand_sale_flows dsf
JOIN dim_region dr
  ON dr.sk_region = dsf.sk_region
),
sale_demand_events AS (
SELECT
	COALESCE(offers.id_user, db.id_visitor) AS id_buyer,
	COALESCE(offers.id_house, db.id_property) AS id_house,
	offers.id_offer,
	offers.form_of_payment,
	offers.dt_offer_sent,
	offers.dt_offer_accepted,
	offers.dt_ccv_signed,
	offers.dt_offer_rejected,
	offers.dt_diligence_started,
	offers.dt_diligence_approved,
	offers.dt_credit_started,
	offers.dt_credit_approved,
	offers.dt_payment_concluded,
	offers.dt_matricula_atualizada,
	offers.dt_entrega_chaves,
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
	sdr.city_group,
	sde.form_of_payment,
	sde.dt_offer_sent,
	sde.dt_offer_accepted,
	sde.dt_ccv_signed,
	sde.dt_offer_rejected,
	sde.dt_diligence_started,
	sde.dt_diligence_approved,
	sde.dt_credit_started,
	sde.dt_credit_approved,
	sde.dt_payment_concluded,
	sde.dt_matricula_atualizada,
	sde.dt_entrega_chaves,
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
LEFT JOIN sale_demand_region sdr
  ON sdr.id_house = sde.id_house
),
p2fc AS (
SELECT
   slf.sk_prospect_date AS base_date,
   slf.city_group,
   slf.lead_context,
   slf.mkt_campaign_context,
   slf.mkt_origin,
   slf.mkt_channel,
   slf.mkt_type,
   NULL AS first_origin_demand,
   NULL AS origin_before_offer,
   NULL AS origin_after_offer,
   NULL AS form_of_payment,
   CASE WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_contact_date,-1)))) < 20
         THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_contact_date,-1))))
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_contact_date,-1)))) >= 20
         THEN 'W20+'
   END AS weeks_conversion,
   COUNT(slf.sk_prospect_date) AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
fc2q AS (
SELECT
	slf.sk_first_contact_date AS base_date,
	slf.city_group,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
  	slf.mkt_channel,
    slf.mkt_type,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_contact_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_contact_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1))))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_contact_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    COUNT(slf.sk_first_contact_date) AS fc2q,
    NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_first_contact_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
p2q AS (
SELECT
	slf.sk_prospect_date AS base_date,
	slf.city_group,
   slf.lead_context,
   slf.mkt_campaign_context,
   slf.mkt_origin,
   slf.mkt_channel,
   slf.mkt_type,
   NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1))))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   COUNT(slf.sk_prospect_date) AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
q2o AS (
SELECT
	slf.sk_qualified_date AS base_date,
	slf.city_group,
   slf.lead_context,
   slf.mkt_campaign_context,
   slf.mkt_origin,
   slf.mkt_channel,
   slf.mkt_type,
   NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1)))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1))))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1)))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	COUNT(slf.sk_qualified_date) AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
o2fl AS (
SELECT
	slf.sk_opportunity_date AS base_date,
	slf.city_group,
   slf.lead_context,
   slf.mkt_campaign_context,
   slf.mkt_origin,
   slf.mkt_channel,
   slf.mkt_type,
   NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1)))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1))))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1)))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	COUNT(slf.sk_opportunity_date) AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_opportunity_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
vb2vc AS (
SELECT
	REPLACE(DATE(dt_created),'-','')::INTEGER AS base_date,
	city_group,
   NULL AS lead_context,
   NULL AS mkt_campaign_context,
   NULL AS mkt_origin,
   NULL AS mkt_channel,
   NULL AS mkt_type,
   first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	COUNT(DISTINCT sk_booking) AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_demand_classification
WHERE date(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
vc2os AS (
SELECT
	REPLACE(DATE(dt_completed),'-','')::INTEGER AS base_date,
	city_group,
   NULL AS lead_context,
   NULL AS mkt_campaign_context,
   NULL AS mkt_origin,
   NULL AS mkt_channel,
   NULL AS mkt_type,
   first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	COUNT(DISTINCT sk_booking) AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_demand_classification
WHERE date(dt_completed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
vb2os AS (
SELECT
	REPLACE(DATE(dt_created),'-','')::INTEGER AS base_date,
	city_group,
   NULL AS lead_context,
   NULL AS mkt_campaign_context,
   NULL AS mkt_origin,
   NULL AS mkt_channel,
   NULL AS mkt_type,
   first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	COUNT(DISTINCT sk_booking) AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_demand_classification
WHERE date(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
os2oa AS (
SELECT
	REPLACE(DATE(dt_offer_sent),'-','')::INTEGER AS base_date,
	city_group,
   NULL AS lead_context,
   NULL AS mkt_campaign_context,
   NULL AS mkt_origin,
   NULL AS mkt_channel,
   NULL AS mkt_type,
   first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	COUNT(DISTINCT id_offer) AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_demand_classification
WHERE date(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
oa2ccv AS (
SELECT
	REPLACE(DATE(dt_offer_accepted),'-','')::INTEGER AS base_date,
	city_group,
   NULL AS lead_context,
   NULL AS mkt_campaign_context,
   NULL AS mkt_origin,
   NULL AS mkt_channel,
   NULL AS mkt_type,
   first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	COUNT(DISTINCT id_offer) AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_demand_classification
WHERE date(dt_offer_accepted) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
ccv2ma AS (
SELECT
	REPLACE(DATE(dt_ccv_signed),'-','')::INTEGER AS base_date,
	city_group,
   NULL AS lead_context,
   NULL AS mkt_campaign_context,
   NULL AS mkt_origin,
   NULL AS mkt_channel,
   NULL AS mkt_type,
   first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_atualizada))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_atualizada)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_atualizada))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	COUNT(DISTINCT id_offer) AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM sale_demand_classification
WHERE DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
ccv2pc AS (
SELECT
	REPLACE(DATE(dt_ccv_signed),'-','')::INTEGER AS base_date,
	city_group,
   NULL AS lead_context,
   NULL AS mkt_campaign_context,
   NULL AS mkt_origin,
   NULL AS mkt_channel,
   NULL AS mkt_type,
   first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	CASE WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_payment_concluded))) < 20
			  THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_payment_concluded)))
	     WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_payment_concluded))) >= 20
	     	  THEN 'W20+'
	END AS weeks_conversion,
	NULL::BIGINT AS p2fc,
   NULL::BIGINT AS fc2q,
   NULL::BIGINT AS p2q,
	NULL::BIGINT AS q2o,
	NULL::BIGINT AS o2fl,
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vc2os,
	NULL::BIGINT AS vb2os,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2ma,
	COUNT(DISTINCT id_offer) AS ccv2pc
FROM sale_demand_classification
WHERE DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
union_all AS (
SELECT * FROM p2fc
	UNION ALL
	SELECT * FROM fc2q
	UNION ALL
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
	UNION ALL
	SELECT * FROM ccv2ma
	UNION ALL
	SELECT * FROM ccv2pc
),
union_all_date AS (
SELECT
	dd.week_start,
	dd.date,
	dd.month,
	dd.quarter,
	ua.city_group,
	ua.lead_context,
	ua.mkt_campaign_context,
	ua.mkt_origin,
	ua.mkt_channel,
	ua.mkt_type,
	ua.first_origin_demand,
	ua.origin_before_offer,
	ua.origin_after_offer,
	ua.form_of_payment,
	ua.weeks_conversion,
	ua.p2fc,
	ua.fc2q,
	ua.p2q,
	ua.q2o,
	ua.o2fl,
	ua.vb2vc,
	ua.vc2os,
	ua.vb2os,
	ua.os2oa,
	ua.oa2ccv,
	ua.ccv2ma,
	ua.ccv2pc
FROM union_all ua
RIGHT JOIN dim_date dd
  ON ua.base_date = dd.sk_date
WHERE dd.date BETWEEN '2020-01-01' AND current_date
)
SELECT
	week_start,
	date,
	month,
	quarter,
	city_group,
	lead_context,
	mkt_campaign_context,
	mkt_origin,
	mkt_channel,
	mkt_type,
	first_origin_demand,
	origin_before_offer,
	origin_after_offer,
	form_of_payment,
	weeks_conversion,
	SUM(p2fc) AS p2fc,
	SUM(fc2q) AS fc2q,
	SUM(p2q) AS p2q,
   SUM(q2o) AS q2o,
	SUM(o2fl) AS o2fl,
	SUM(vb2vc) AS vb2vc,
	SUM(vc2os) AS vc2os,
	SUM(vb2os) AS vb2os,
	SUM(os2oa) AS os2oa,
	SUM(oa2ccv) AS oa2ccv,
	sum(ccv2ma) AS ccv2ma,
	sum(ccv2pc) AS ccv2pc,
	current_timestamp AS ts_load
FROM union_all_date
GROUP BY week_start,
	 date,
	 month,
	 quarter,
	 city_group,
	 lead_context,
	 mkt_campaign_context,
	 mkt_origin,
	 mkt_channel,
	 mkt_type,
	 first_origin_demand,
	 origin_before_offer,
	 origin_after_offer,
	 form_of_payment,
	 weeks_conversion;