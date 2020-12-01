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
payment_method_adjusted AS (
-- data from datalake_firestore_prod.sale_offer
SELECT
    so.id,
	so.id_house,
	so.current_payment_method AS form_of_payment
FROM datalake_firestore_prod.sale_offer so
),
monday_adjusted AS (
-- data from datalake_firestore_prod.monday
SELECT
	mo.id_offer,
	mo.id_buyer||'_'||mo.id_house AS sale_flow,
	mo.id_house,
	mo.id_buyer AS id_user,
	mo.dt_submitted AS dt_offer_sent,
	mo.dt_deal_qualified AS dt_deal_qualified,
	mo.dt_accepted AS dt_offer_accepted,
	mo.dt_sale_agreement_signed AS dt_ccv_signed,
	mo.dt_offer_dismissed AS dt_offer_rejected,
	mo.dt_legaut_analysis_started AS dt_diligence_started_legaut,
	mo.dt_legaut_analysis_ended AS dt_diligence_ended_legaut,
	mo.dt_legal_analysis_ended AS dt_diligence_ended,
	mo.dt_legal_risk_started AS dt_diligence_started_legal,
	mo.dt_legal_risk_ended AS dt_diligence_ended_legal,
	mo.dt_credit_analysis_started AS dt_credit_started,
	mo.dt_credit_analysis_ended AS dt_credit_approved,
	mo.dt_sale_transacton_paid AS dt_payment_concluded,
	mo.dt_notes_registry_ended AS dt_notes_registry_ended,
	mo.dt_house_registry_ended AS dt_matricula_atualizada,
	mo.dt_sale_key_delivered AS dt_entrega_chaves,
	mo.dt_financing_started AS dt_finan_started,
	mo.dt_financing_ended AS dt_finan_ended,
	drop_reason_before_acceptance AS offer_rejection_reason,
	drop_reason_after_acceptance AS offer_accepted_drop_reason,
	mo.listing_sale_price AS sale_listing_price,
	mo.price_offered_by_buyer AS buyer_offer_price,
	(mo.listing_sale_price - mo.price_offered_by_buyer)/mo.listing_sale_price AS offer_discount
FROM
	datalake_firestore_prod.monday AS mo
),
monday_manual AS (
SELECT
	NULLIF(mo.name,'') AS id_offer,
	TO_DATE(SUBSTRING(NULLIF(mo.data_assinatura_ccv, ''),1,10), 'yyyy-mm-dd') AS dt_ccv_signed_man,
	TO_DATE(SUBSTRING(NULLIF(mo.diligencia_inicio, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_started_legaut_man,
	TO_DATE(SUBSTRING(NULLIF(mo.diligencia_retorno_buyer_seller, ''),1,10), 'yyyy-mm-dd') AS dt_diligence_ended_man,
	TO_DATE(SUBSTRING(NULLIF(mo.credito_fim, ''),1,10), 'yyyy-mm-dd') AS dt_credit_approved_man,
	TO_DATE(SUBSTRING(NULLIF(mo.data_chaves_buyer, ''),1,10), 'yyyy-mm-dd') AS dt_entrega_chaves_man
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
sale_closing AS (
    WITH fact_os AS (
    SELECT
        DATE_TRUNC('week', DATE(sk_offer_submitted_date)) AS week_start,
        DATE(sk_offer_submitted_date) AS date,
        sk_offer
    FROM
    	sale.fact_offers
    WHERE
    	sk_offer_submitted_date > 0
    ),
    fact_oa AS (
    SELECT
        DATE_TRUNC('week', DATE(sk_offer_accepted_date)) AS week_start,
        DATE(sk_offer_accepted_date) AS date,
        sk_offer
    FROM
        sale.fact_offers
    WHERE
        sk_offer_accepted_date > 0
    ),
    fact_ccv AS (
    SELECT
        DATE_TRUNC('week', DATE(ts_sale_agreement_signed)) AS week_start,
        DATE(ts_sale_agreement_signed) AS date,
        sk_offer
    FROM
        sale.dim_sale_agreement
    WHERE
        ts_sale_agreement_signed IS NOT NULL
    )
SELECT
    COALESCE(COALESCE(fact_os.sk_offer, fact_oa.sk_offer), fact_ccv.sk_offer) AS sk_offer,
    MAX(fact_os.date) AS os_date,
    MAX(fact_oa.date) AS oa_date,
    MAX(fact_ccv.date) AS ccv_date
FROM
    fact_os
FULL OUTER JOIN
    fact_oa
        ON fact_os.sk_offer = fact_oa.sk_offer
        AND fact_os.date = fact_oa.date
FULL OUTER JOIN
    fact_ccv
        ON fact_os.sk_offer = fact_ccv.sk_offer
        AND fact_os.date = fact_ccv.date
GROUP BY 1
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
	fsf.sk_house::VARCHAR AS id_house,
	dr.city_group
FROM sale.fact_sale_flows fsf
JOIN dim_region dr
  ON dr.sk_region = fsf.sk_region
),
sale_demand_events AS (
SELECT
	COALESCE(offers.id_user, db.id_visitor, tta.tenant_id::BIGINT) AS id_buyer,
	COALESCE(offers.id_house, db.id_property, tta.house_id::BIGINT) AS id_house,
	offers.dt_offer_sent,
	offers.dt_deal_qualified,
	offers.dt_offer_accepted,
	offers.dt_ccv_signed,
	COALESCE(offers.id_offer,sc.sk_offer, mom.id_offer) AS id_offer,
	offers.dt_diligence_started_legaut,
	offers.dt_diligence_ended_legaut,
	offers.dt_diligence_ended,
	offers.dt_diligence_started_legal,
	offers.dt_diligence_ended_legal,
	offers.dt_credit_started,
	offers.dt_credit_approved,
	offers.dt_payment_concluded,
	offers.dt_notes_registry_ended,
	offers.dt_matricula_atualizada,
	offers.dt_entrega_chaves,
	offers.dt_finan_started,
	offers.dt_finan_ended,
	db.sk_booking,
	db.dt_created,
	db.dt_completed,
	tta.tta_id,
	tta.first_message_ts::TIMESTAMP AS tta_started,
	tta.first_attendance_ts::TIMESTAMP AS tta_completed,
	sc.os_date,
	sc.oa_date,
	sc.ccv_date,
	mom.dt_ccv_signed_man,
	mom.dt_diligence_started_legaut_man,
	mom.dt_diligence_ended_man,
	mom.dt_credit_approved_man,
	mom.dt_entrega_chaves_man
FROM monday_adjusted offers
FULL OUTER JOIN sale_bookings db
  ON (offers.id_house = db.id_property AND offers.id_user = db.id_visitor)
FULL OUTER JOIN sale_tta tta
  ON (offers.id_house = tta.house_id AND offers.id_user = tta.tenant_id)
FULL OUTER JOIN
	sale_closing AS sc
		ON offers.id_offer = sc.sk_offer
FULL OUTER JOIN
	monday_manual AS mom
		ON offers.id_offer = mom.id_offer
),
sale_demand_classification AS (
SELECT
	sde.id_buyer,
	sde.id_house,
	sdr.city_group,
	pma.form_of_payment,
	--sde.dt_offer_sent,
	sde.os_date AS dt_offer_sent,
	sde.dt_deal_qualified,
	--sde.dt_offer_accepted,
	--sde.dt_ccv_signed,
	sde.oa_date AS dt_offer_accepted,
	sde.dt_ccv_signed_man AS dt_ccv_signed,
	sde.id_offer,
	sde.sk_booking,
	sde.dt_created,
	sde.dt_completed,
	sde.tta_id,
	sde.tta_started,
	sde.tta_completed,
	sde.dt_diligence_started_legaut_man AS dt_diligence_started_legaut,
	sde.dt_diligence_ended_legaut,
	sde.dt_diligence_ended_man AS dt_diligence_ended,
	sde.dt_diligence_started_legal,
	sde.dt_diligence_ended_legal,
	sde.dt_credit_started,
	sde.dt_credit_approved_man AS dt_credit_approved,
	sde.dt_payment_concluded,
	sde.dt_notes_registry_ended,
	sde.dt_matricula_atualizada,
	sde.dt_entrega_chaves_man AS dt_entrega_chaves,
	sde.dt_finan_started,
	sde.dt_finan_ended,
	fsf.first_event AS first_touchpoint,
	fsf.higher_intent_before_offer,
	fsf.higher_intent_after_offer
FROM sale_demand_events sde
LEFT JOIN
	sale.fact_sale_flows AS fsf
		ON sde.id_buyer = fsf.sk_buyer::VARCHAR
		AND sde.id_house = fsf.sk_house::VARCHAR
LEFT JOIN sale_demand_region sdr
  ON sdr.id_house::VARCHAR = sde.id_house
LEFT JOIN
	payment_method_adjusted AS pma
		ON pma.id = sde.id_offer
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
offers_deal_qualified AS (
SELECT
	REPLACE(DATE(dt_deal_qualified),'-','')::INTEGER AS base_date,
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
	COUNT(DISTINCT id_offer) AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
	sale_demand_classification
WHERE
	DATE(dt_deal_qualified) > 0
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	COUNT(DISTINCT id_offer) AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	COUNT(DISTINCT id_offer) AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	COUNT(DISTINCT id_offer) AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	NULL::BIGINT AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
	NULL::BIGINT AS offers_accepted,
	NULL::BIGINT AS ccv_signed,
	NULL::BIGINT AS diligence_started_legaut,
	NULL::BIGINT AS diligence_ended_legaut,
	NULL::BIGINT AS diligence_ended,
	NULL::BIGINT AS diligence_started_legal,
	NULL::BIGINT AS diligence_ended_legal,
	NULL::BIGINT AS credit_sent,
	NULL::BIGINT AS credit_approved,
	COUNT(DISTINCT id_offer) AS finan_started,
	NULL::BIGINT AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	COUNT(DISTINCT id_offer) AS finan_ended,
	NULL::BIGINT AS payment_concluded,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM sale_demand_classification
WHERE DATE(dt_finan_ended) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
notes_registry_ended AS (
SELECT
	REPLACE(DATE(dt_notes_registry_ended),'-','')::INTEGER AS base_date,
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
	NULL::BIGINT AS deal_qualified,
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
	COUNT(DISTINCT id_offer) AS notes_registry_ended,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
	sale_demand_classification
WHERE
	DATE(dt_notes_registry_ended) > 0
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	NULL::BIGINT AS deal_qualified,
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
	NULL::BIGINT AS notes_registry_ended,
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
	SELECT * FROM offers_deal_qualified
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
	SELECT * FROM notes_registry_ended
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
	ua.deal_qualified,
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
	ua.notes_registry_ended,
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
	SUM(deal_qualified) AS deal_qualified,
	SUM(offers_accepted) AS offer_accepted,
	SUM(ccv_signed) AS ccv_signed,
	SUM(diligence_started_legaut) AS diligence_started_legaut,
	SUM(diligence_ended_legaut) AS diligence_ended_legaut,
	SUM(diligence_ended) AS diligence_ended,
	SUM(diligence_started_legal) AS diligence_started_legal,
	SUM(diligence_ended_legal) AS diligence_ended_legal,
	SUM(credit_sent) AS credit_sent,
	SUM(credit_approved) AS credit_approved,
	SUM(finan_started) AS finan_started,
	SUM(finan_ended) AS finan_ended,
	SUM(payment_concluded) AS payment_concluded,
	SUM(notes_registry_ended) AS notes_registry_ended,
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
	 form_of_payment
