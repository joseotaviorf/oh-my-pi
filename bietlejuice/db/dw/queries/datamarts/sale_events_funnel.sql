WITH
sale_listing_flows_adjust AS (
SELECT
	lf.sk_lead_date,
	lf.sk_lead,
	lf.sk_first_contact_date,
	lf.sk_prospect_date,
	lf.sk_qualified_date,
	lf.sk_opportunity_date,
	lf.sk_first_listing_date,
	lf.sk_house_listing,
	lf.mkt_origin,
	lf.mkt_channel,
	CASE
	    WHEN lf.mkt_origin = 'B2B' then lf.mkt_origin
	    WHEN lf.mkt_completion = 'Full Self-Service' then 'FSS'
	    WHEN (dl.sales_company = 'ACTION_LINE' and has_isales_intervention = true) OR (dl.sales_company = 'ATENTO' and has_isales_intervention = true) then 'OUT'
	    else 'ISS'
	END AS lead_context,
	CASE WHEN lf.lead_context_origin = 'Organic' THEN 'Branded'
         ELSE lead_context_origin
	END AS mkt_campaign_context,
	CASE WHEN lf.mkt_channel IN ('CRM/Notification','Backend','Branding','Other') THEN 'Paid'
         ELSE 'Non Paid'
	END AS mkt_type,
	CASE WHEN dr.city_group NOT IN ('RMSP', 'Rio de Janeiro') THEN NULL ELSE dr.city_group END AS city_group
FROM sale.fact_listing_flows lf
LEFT JOIN dim_lead dl
  ON dl.sk_lead = lf.sk_lead
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
	TO_DATE(SUBSTRING(NULLIF(mo.diligencia_inicio, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_started_legaut,
	TO_DATE(SUBSTRING(NULLIF(mo.dd_retorno_legaut, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_ended_legaut,
	TO_DATE(SUBSTRING(NULLIF(mo.diligencia_retorno_buyer_seller, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_ended,
	TO_DATE(SUBSTRING(NULLIF(mo.dd_inicio_legal, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_started_legal,
	TO_DATE(SUBSTRING(NULLIF(mo.dd_fim_legal, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_ended_legal,
	TO_DATE(SUBSTRING(NULLIF(mo.credito_inicio, ''),1,10), 'yyyy-mm-dd') AS dt_credit_started,
	TO_DATE(SUBSTRING(NULLIF(mo.credito_fim, ''),1,10), 'yyyy-mm-dd') AS dt_credit_approved,
	TO_DATE(SUBSTRING(NULLIF(mo.data_pagto_seller, ''),1,10), 'yyyy-mm-dd') AS dt_payment_concluded,
	TO_DATE(SUBSTRING(NULLIF(mo.cri_fim, ''),1,10), 'yyyy-mm-dd') AS dt_matricula_atualizada,
	TO_DATE(SUBSTRING(NULLIF(mo.data_chaves_buyer, ''),1,10), 'yyyy-mm-dd') AS dt_entrega_chaves,
	TO_DATE(SUBSTRING(NULLIF(mo.finan_inicio, ''),1,10), 'yyyy-mm-dd') AS dt_finan_started,
	TO_DATE(SUBSTRING(NULLIF(mo.finan_fim, ''),1,10), 'yyyy-mm-dd') AS dt_finan_ended,
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
	COALESCE(offers.id_user, db.id_visitor, tta.tenant_id::BIGINT) AS id_buyer,
	COALESCE(offers.id_house, db.id_property, tta.house_id::BIGINT) AS id_house,
	offers.form_of_payment,
	offers.dt_offer_sent,
	offers.dt_offer_accepted,
	offers.dt_ccv_signed,
	offers.id_offer,
	offers.dt_diligence_started_legaut,
	offers.dt_diligence_ended_legaut,
	offers.dt_diligence_ended,
	offers.dt_diligence_started_legal,
	offers.dt_diligence_ended_legal,
	offers.dt_credit_started,
	offers.dt_credit_approved,
	offers.dt_payment_concluded,
	offers.dt_matricula_atualizada,
	offers.dt_entrega_chaves,
	offers.dt_finan_started,
	offers.dt_finan_ended,
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
	sdr.city_group,
	sde.form_of_payment,
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
	sde.dt_diligence_started_legaut,
	sde.dt_diligence_ended_legaut,
	sde.dt_diligence_ended,
	sde.dt_diligence_started_legal,
	sde.dt_diligence_ended_legal,
	sde.dt_credit_started,
	sde.dt_credit_approved,
	sde.dt_payment_concluded,
	sde.dt_matricula_atualizada,
	sde.dt_entrega_chaves,
	sde.dt_finan_started,
	sde.dt_finan_ended,
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
lead_ AS (
SELECT
	slf.sk_lead_date AS base_date,
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
   COUNT(slf.sk_lead_date) AS leads,
   NULL::BIGINT AS prospects,
   NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_lead_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
prospect AS (
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
   NULL::BIGINT AS leads,
   COUNT(slf.sk_prospect_date) AS prospects,
   NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
first_contacts AS (
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
   NULL::BIGINT AS leads,
   NULL::BIGINT AS prospects,
   COUNT(slf.sk_first_contact_date) AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_first_contact_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
qualified AS (
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
   NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
opportunity AS (
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
   NULL::BIGINT AS leads,
   NULL::BIGINT AS prospects,
   NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_opportunity_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
first_listing AS (
SELECT
   slf.sk_first_listing_date AS base_date,
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
   NULL::BIGINT AS leads,
   NULL::BIGINT AS prospects,
   NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_listing_flows_adjust AS slf
WHERE slf.sk_first_listing_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
tta_sent AS (
SELECT
   REPLACE(DATE(tta_started),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(tta_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
tta_completed AS (
SELECT
	REPLACE(DATE(tta_completed),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(tta_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
visits_booked AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
visits_completed AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_completed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
offers_sent AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
offers_accepted AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_offer_accepted) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
ccv_signed AS (
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
diligence_started_legaut AS (
SELECT
	REPLACE(DATE(dt_diligence_started_legaut),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	COUNT(DISTINCT id_offer) AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_diligence_started_legaut) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
diligence_ended_legaut AS (
SELECT
	REPLACE(DATE(dt_diligence_ended_legaut),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	COUNT(DISTINCT id_offer) AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_diligence_ended_legaut) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
diligence_ended AS (
SELECT
	REPLACE(DATE(dt_diligence_ended),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
   NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	COUNT(DISTINCT id_offer) AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_diligence_ended) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
diligence_started_legal AS (
SELECT
	REPLACE(DATE(dt_diligence_started_legal),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
   NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	COUNT(DISTINCT id_offer) AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_diligence_started_legal) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
diligence_ended_legal AS (
SELECT
	REPLACE(DATE(dt_diligence_ended_legal),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
   NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	COUNT(DISTINCT id_offer) AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_diligence_ended_legal) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
credit_sent AS (
SELECT
	REPLACE(DATE(dt_credit_started),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	COUNT(DISTINCT id_offer) AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_credit_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
credit_approved AS (
SELECT
	REPLACE(DATE(dt_credit_approved),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	COUNT(DISTINCT id_offer) AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_credit_approved) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
finan_started AS (
SELECT
	REPLACE(DATE(dt_finan_started),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	COUNT(DISTINCT id_offer) AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_finan_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
finan_ended AS (
SELECT
	REPLACE(DATE(dt_finan_ended),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS finan_started,
	COUNT(DISTINCT id_offer) AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_finan_ended) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
payment_concluded AS (
SELECT
	REPLACE(DATE(dt_payment_concluded),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	COUNT(DISTINCT id_offer) AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_payment_concluded) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
matricula_atualizada AS (
SELECT
	REPLACE(DATE(dt_matricula_atualizada),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	COUNT(DISTINCT id_offer) AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_matricula_atualizada) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
entrega_chave AS (
SELECT
	REPLACE(DATE(dt_entrega_chaves),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS leads,
	NULL::BIGINT AS prospects,
	NULL::BIGINT AS first_contacts,
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
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS matricula_atualizada,
	COUNT(DISTINCT id_offer) AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_entrega_chaves) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
union_all AS (
SELECT * FROM lead_
	UNION ALL
	SELECT * FROM prospect
	UNION ALL
	SELECT * FROM first_contacts
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
	SELECT * FROM diligence_started_legaut
	UNION ALL
	SELECT * FROM diligence_ended_legaut
	UNION ALL
	SELECT * FROM diligence_ended
	UNION ALL
	SELECT * FROM diligence_started_legal
	UNION ALL
	SELECT * FROM diligence_ended_legal
	UNION ALL
	SELECT * FROM credit_sent
	UNION ALL
	SELECT * FROM credit_approved
	UNION ALL
	SELECT * FROM finan_started
	UNION ALL
	SELECT * FROM finan_ended
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
	ua.leads,
	ua.prospects,
	ua.first_contacts,
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
	ua.diligence_started_legaut,
	ua.diligence_ended_legaut,
	ua.diligence_ended,
	ua.diligence_started_legal,
	ua.diligence_ended_legal,
	ua.credit_sent,
	ua.credit_approved,
	ua.finan_started,
	ua.finan_ended,
	ua.payment_concluded,
	ua.matricula_atualizada,
	ua.entrega_chave
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
	SUM(leads) AS leads,
   SUM(prospects) AS prospects,
   SUM(first_contacts) AS first_contacts,
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
	SUM(diligence_started_legaut) AS diligence_started_legaut,
	SUM(diligence_ended_legaut) AS diligence_ended_legaut,
	SUM(diligence_started_legal) AS diligence_started_legal,
	SUM(diligence_ended_legal) AS diligence_ended_legal,
	SUM(diligence_ended) AS diligence_ended,
	SUM(credit_sent) AS credit_sent,
	SUM(credit_approved) AS credit_approved,
	SUM(finan_started) AS finan_started,
	SUM(finan_ended) AS finan_ended,
	SUM(payment_concluded) AS payment_concluded,
	SUM(matricula_atualizada) AS matricula_atualizada,
	SUM(entrega_chave) AS entrega_chave,
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
	 form_of_payment;
