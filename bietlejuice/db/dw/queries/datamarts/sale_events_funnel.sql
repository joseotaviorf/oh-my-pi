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
	CASE WHEN db.status = 'Realizado' and db.visit_follow_up in ('VaiNegociar', 'NaoGostou', 'VisitouSozinho', 'Talvez') THEN db.dt_scheduling END AS dt_completed
FROM dim_booking db
WHERE db.visit_intent = 'SALE'
  AND db.type = 'Visita'
),
sale_tta AS (
SELECT
	tta.house_id::BIGINT AS house_id,
	tta.tenant_id::BIGINT AS tenant_id,
	(tta.sk_house_listing || tta.tenant_id || tta.agent_id) AS tta_id,
	tta.first_message_ts,
	tta.first_attendance_ts
FROM datamarts.talk_to_agent tta
WHERE tta.business_context = 'SALE'
),
sale_demand_events AS (
SELECT
	COALESCE(offers.id_user, db.id_visitor, tta.tenant_id::BIGINT) AS id_buyer,
	COALESCE(offers.id_house, db.id_property, tta.house_id::BIGINT) AS id_house,
	offers.dt_offer_sent,
	offers.dt_offer_accepted,
	offers.dt_ccv_signed,
	offers.id_offer,
	offers.dt_diligence_started,
	offers.dt_diligence_approved,
	offers.dt_credit_started,
	offers.dt_credit_approved,
	offers.dt_payment_concluded,
	offers.dt_matricula_atualizada,
	offers.dt_entrega_chaves,
	db.sk_booking,
	db.dt_created,
	db.dt_completed,
	tta.tta_id,
	tta.first_message_ts::TIMESTAMP AS tta_started,
	tta.first_attendance_ts::TIMESTAMP AS tta_completed
FROM monday_adjusted offers
FULL OUTER JOIN sale_bookings db
  ON (offers.id_house = db.id_property AND offers.id_user = db.id_visitor)
FULL OUTER JOIN sale_tta tta
  ON (offers.id_house = tta.house_id AND offers.id_user = tta.tenant_id)
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
	sde.tta_id,
	sde.tta_started,
	sde.tta_completed,
	sde.dt_diligence_started,
	sde.dt_diligence_approved,
	sde.dt_credit_started,
	sde.dt_credit_approved,
	sde.dt_payment_concluded,
	sde.dt_matricula_atualizada,
	sde.dt_entrega_chaves,
	dsf.first_event AS first_touchpoint,
	dsf.higher_intent_before_offer,
	dsf.higher_intent_after_offer
FROM sale_demand_events sde
LEFT JOIN datamarts.demand_sale_flows dsf
  ON sde.id_buyer = dsf.id_buyer
  AND sde.id_house = dsf.id_house
),
lead_ AS (
SELECT
	slf.sk_lead_date AS date_,
   	slf.lead_context,
   	slf.mkt_campaign_context,
   	slf.mkt_origin,
   	slf.mkt_channel,
   	slf.mkt_type,
	NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
   	COUNT(slf.sk_lead_date) AS leads,
   	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_lead_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9
),
prospect AS (
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
   	NULL::BIGINT AS leads,
   	COUNT(slf.sk_prospect_date) AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9
),
qualified AS (
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
   	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	COUNT(slf.sk_qualified_date) AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9
),
opportunity AS (
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
   	NULL::BIGINT AS leads,
   	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	COUNT(DISTINCT slf.sk_house_listing) AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_opportunity_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9
),
first_listing AS (
SELECT
   	slf.sk_first_listing_date AS date_,
   	slf.lead_context,
   	slf.mkt_campaign_context,
   	slf.mkt_origin,
   	slf.mkt_channel,
	slf.mkt_type,
   	NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
   	NULL::BIGINT AS leads,
   	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	COUNT(DISTINCT slf.sk_house_listing) AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
   	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_first_listing_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9
),
tta_sent AS (
SELECT
   	REPLACE(DATE(tta_started),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
   	NULL AS mkt_channel,
   	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	COUNT(DISTINCT tta_id) AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
tta_completed AS (
SELECT
	REPLACE(DATE(tta_completed),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
   	NULL AS mkt_channel,
   	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	COUNT(DISTINCT tta_id) AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
visits_booked AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	COUNT(DISTINCT sk_booking) AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
visits_completed AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	COUNT(DISTINCT sk_booking) AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
offers_sent AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	COUNT(DISTINCT id_offer) AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
offers_accepted AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	COUNT(DISTINCT id_offer) AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
ccv_signed AS (
SELECT
	REPLACE(DATE(dt_ccv_signed),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	COUNT(DISTINCT id_offer) AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
diligence_sent AS (
SELECT
	REPLACE(DATE(dt_diligence_started),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	COUNT(DISTINCT id_offer) AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
diligence_accepted AS (
SELECT
	REPLACE(DATE(dt_diligence_approved),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	COUNT(DISTINCT id_offer) AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
credit_sent AS (
SELECT
	REPLACE(DATE(dt_credit_started),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	COUNT(DISTINCT id_offer) AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
credit_approved AS (
SELECT
	REPLACE(DATE(dt_credit_approved),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	COUNT(DISTINCT id_offer) AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
payment_concluded AS (
SELECT
	REPLACE(DATE(dt_payment_concluded),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	COUNT(DISTINCT id_offer) AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
matricula_atualizada AS (
SELECT
	REPLACE(DATE(dt_matricula_atualizada),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	COUNT(DISTINCT id_offer) AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
),
entrega_chave AS (
SELECT
	REPLACE(DATE(dt_entrega_chaves),'-','')::INTEGER AS date_,
	NULL AS lead_context,
   	NULL AS mkt_campaign_context,
   	NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS qualifieds,
	NULL::BIGINT AS opportunities,
	NULL::BIGINT AS first_listings,
	NULL::BIGINT AS tta_started,
	NULL::BIGINT AS tta_completed,
	NULL::BIGINT AS visits_booked,
   	NULL::BIGINT AS visits_completed,
	NULL::BIGINT AS offers_submitted,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_sent,
	NULL::BIGINT AS diligence_accepted,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	COUNT(DISTINCT id_offer) AS entrega_chave
FROM sale_demand_classification
GROUP BY 1,2,3,4,5,6,7,8,9
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
	SELECT * FROM first_listing
	UNION ALL
	SELECT * FROM tta_sent
	UNION ALL
	SELECT * FROM tta_completed
	UNION ALL
	SELECT * FROM visits_booked
	UNION ALL
	SELECT * FROM visits_completed
	UNION ALL
	SELECT * FROM offers_sent
	UNION ALL
	SELECT * FROM offers_accepted
	UNION ALL
	SELECT * FROM ccv_signed
	UNION ALL
	SELECT * FROM diligence_sent
	UNION ALL
	SELECT * FROM diligence_accepted
	UNION ALL
	SELECT * FROM credit_sent
	UNION ALL
	SELECT * FROM credit_approved
	UNION ALL
	SELECT * FROM payment_concluded
	UNION ALL
	SELECT * FROM matricula_atualizada
	UNION ALL
	SELECT * FROM entrega_chave
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
	ua.leads,
	ua.prospects,
	ua.qualifieds,
	ua.opportunities,
	ua.first_listings,
	ua.tta_started,
	ua.tta_completed,
	ua.visits_booked,
	ua.visits_completed,
	ua.offers_submitted,
	ua.offers_accepted,
	ua.ccv_signed,
	ua.diligence_sent,
	ua.diligence_accepted,
	ua.credit_sent,
	ua.credit_approved,
	ua.payment_concluded,
	ua.matricula_atualizada,
	ua.entrega_chave
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
	SUM(leads) AS leads,
   	SUM(prospects) AS prospects,
	SUM(qualifieds) AS qualifieds,
	SUM(opportunities) AS opportunities,
	SUM(first_listings) AS first_listings,
	SUM(tta_started) AS tta_started,
	SUM(tta_completed) AS tta_completed,
	SUM(visits_booked) AS visits_booked,
	SUM(visits_completed) AS visits_completed,
	SUM(offers_submitted) AS offer_submitted,
	SUM(offers_accepted) AS offer_accepted,
	SUM(ccv_signed) AS ccv_signed,
	SUM(diligence_sent) AS diligence_sent,
	SUM(diligence_accepted) AS diligence_accepted,
	SUM(credit_sent) AS credit_sent,
	SUM(credit_approved) AS credit_approved,
	SUM(payment_concluded) AS payment_concluded,
	SUM(matricula_atualizada) AS matricula_atualizada,
	SUM(entrega_chave) AS entrega_chave,
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
	 origin_after_offer;
