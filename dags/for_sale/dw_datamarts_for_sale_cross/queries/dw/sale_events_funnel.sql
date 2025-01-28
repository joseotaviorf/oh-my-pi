WITH sale_listing_flows_adjust AS (
SELECT
    lf.sk_lead_date,
    lf.sk_lead,
    lf.sk_first_contact_date,
    lf.sk_prospect_date,
    lf.sk_qualified_date,
	lf.sk_available_qualified_date,
    lf.sk_opportunity_date,
    lf.sk_first_listing_date,
    lf.sk_house_listing,
    lf.mkt_origin,
    lf.mkt_channel,
	lf.mkt_medium,
    lf.sales_company,
    CASE WHEN dhl.is_3p_supply THEN 1 ELSE 0 END AS is_3p_supply,
    dhl.partner_3p_supply AS supply_3p_partner,
    CASE WHEN rbh.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
	rbh.partner AS supply_3pbh_partner,
    CASE
        WHEN lf.mkt_origin = 'B2B' OR lf.mkt_origin = 'CIQ' THEN lf.mkt_origin
        WHEN lf.mkt_completion = 'Full Self-Service' THEN 'FSS'
        ELSE 'IS'
    END AS lead_context,
    CASE
        WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other')
            AND lf.mkt_origin NOT IN ('B2B', 'CIQ') THEN 'IS'
        ELSE sourcing_ops
    END AS lead_processing_operation,
    CASE
        WHEN lf.lead_context_origin = 'Organic' THEN 'Branded'
        ELSE lead_context_origin
    END AS mkt_campaign_context,
    CASE
        WHEN lf.mkt_origin IN ('Indica Aí - Agents','Indica Aí - General', 'Price Calculator', 'B2B', 'CIQ', 'Doorman') THEN 'Paid'
        WHEN lf.mkt_origin IN ('Other', 'Backend','Inbound') THEN 'Non Paid'
        WHEN lf.mkt_channel IN ('CRM/Notification', 'LeadEnrichment', 'Organic') AND lf.mkt_origin = 'Owner PWA' THEN 'Non Paid'
        WHEN lf.mkt_channel = 'Paid' AND lf.mkt_origin = 'Owner PWA' THEN 'Paid'
    END AS mkt_type,
    CASE
        WHEN dr.city_group NOT IN ('RMSP', 'Rio de Janeiro','Belo Horizonte','Porto Alegre','Campinas') THEN 'Out of coverage area'
        WHEN dr.city_group IN ('RMSP', 'Rio de Janeiro','Belo Horizonte','Porto Alegre','Campinas') THEN dr.city_group
    END AS city_group,
	ac.affiliate_volumetry
FROM
    dw_datamarts.lead_listing_flows AS lf
LEFT JOIN
    dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = lf.sk_user_lead_affiliate AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
LEFT JOIN
    dw_public.dim_region dr
        ON dr.sk_region = lf.sk_region
LEFT JOIN
    dw_rent.dim_house_listing AS dhl
    	ON dhl.sk_house_listing = lf.sk_house_listing
LEFT JOIN
    datalake_ebdb_listing.house AS rbh
    	ON rbh.id = lf.sk_house_listing / 1000
			AND rbh.is_3p_supply_bh
WHERE lf.origin_table = 'Sale'
),
data_deal_quali AS (
    SELECT
        id,
        DATE(MIN(ts_updated)) AS dt_deal_qualified
    FROM
        datalake_sales_flow_clean.sales_flow_aud
    WHERE
        mod_flow_step AND flow_step = 'PROPOSAL_ONGOING'
    GROUP BY id
),

sale_offers_adjusted AS (
SELECT
    eso.id_offer,
    eso.id_buyer||'_'||eso.id_house AS sale_flow,
    eso.id_house,
    eso.id_buyer AS id_user,
    eso.id_agent,
    CASE
        WHEN eso.current_payment_method = 'FINANCED' AND eso.has_used_fgts_in_payment = FALSE THEN 'Financiado'
        WHEN eso.current_payment_method = 'CASH' AND eso.has_used_fgts_in_payment = FALSE THEN 'À Vista'
        WHEN eso.current_payment_method = 'CASH' AND eso.has_used_fgts_in_payment = TRUE THEN 'À Vista + FGTS'
        WHEN (eso.current_payment_method = 'FINANCED' AND eso.has_used_fgts_in_payment = TRUE) OR eso.current_payment_method = 'FINANCED_WITH_FGTS' THEN 'Financiado + FGTS'
	ELSE 'Other'END AS form_of_payment,
    eso.is_3p_supply,
    COALESCE(eso.partner_3p_supply, '') AS supply_3p_partner,
    eso.is_3p_demand,
    COALESCE(eso.partner_3p_demand, '') AS demand_3p_partner,
    DATE(eso.ts_offer_submitted) AS dt_offer_sent,
    COALESCE(ddq.dt_deal_qualified, m.dt_deal_qualified) AS dt_deal_qualified,
    eso.dt_offer_accepted AS dt_offer_accepted,
    eso.dt_sale_agreement_signed AS dt_ccv_signed,
    DATE(eso.dt_offer_dismissed) AS dt_offer_rejected,
    COALESCE(sof.dt_legaut_analysis_started, m.dt_legaut_analysis_started) AS dt_diligence_started_legaut,
    COALESCE(sof.dt_legaut_analysis_ended, m.dt_legaut_analysis_ended) AS dt_diligence_ended_legaut,
    COALESCE(sof.dt_legal_analysis_ended, m.dt_legal_analysis_ended) AS dt_diligence_ended,
    COALESCE(sof.dt_legal_risk_started, m.dt_legal_risk_started) AS dt_diligence_started_legal,
    COALESCE(sof.dt_legal_risk_ended, m.dt_legal_risk_ended) AS dt_diligence_ended_legal,
    COALESCE(sof.dt_credit_analysis_started, m.dt_credit_analysis_started) AS dt_credit_started,
    COALESCE(sof.dt_credit_analysis_ended, m.dt_credit_analysis_ended) AS dt_credit_approved,
    eso.dt_sale_transacton_paid AS dt_payment_concluded,
    COALESCE(sof.dt_notes_registry_started, m.dt_notes_registry_started) AS dt_notes_registry_started,
    COALESCE(sof.dt_notes_registry_ended, m.dt_notes_registry_ended) AS dt_notes_registry_ended,
    eso.dt_house_registry_started AS dt_matricula_inicio,
    eso.dt_house_registry_ended AS dt_matricula_atualizada,
    COALESCE(sof.dt_sale_key_delivered, m.dt_sale_key_delivered) AS dt_entrega_chaves,
    COALESCE(sof.dt_financing_started, m.dt_financing_started) AS dt_finan_started,
    COALESCE(sof.dt_financing_ended, m.dt_financing_ended) AS dt_finan_ended,
    dl.price AS sale_listing_price,
    eso.first_price_offered_by_buyer AS buyer_offer_price,
    (dl.price - eso.first_price_offered_by_buyer)/dl.price AS offer_discount
FROM
	datalake_offer.sale_offer AS eso
LEFT JOIN
    dw_sale.dim_listing AS dl
      ON eso.id_house = dl.sk_house
LEFT JOIN
    datalake_sale_offer_flows.sale_offer_flows AS sof
      ON eso.id_offer = sof.id_offer
LEFT JOIN
    data_deal_quali AS ddq
      ON sof.id_sales_flow = ddq.id
LEFT JOIN
    datalake_firestore.monday AS m
      ON eso.id_offer = m.id_offer
)
,
sale_bookings_base AS (
SELECT
    fv.sk_house AS id_property,
    fv.sk_buyer AS id_visitor,
    fv.sk_agent AS id_agent,
    fv.sk_offer,
    fv.sk_booking,
    fv.is_hub_flow,
	hs.hub_name AS hub_visit,
    dr.city_group,
	COALESCE(db.is_3p_demand, FALSE) AS is_3p_demand,
	COALESCE(db.partner_3p_demand, '') AS demand_3p_partner,
	COALESCE(db.is_3p_supply, FALSE) AS is_3p_supply,
	COALESCE(db.partner_3p_supply, '') AS supply_3p_partner,
    DATE(NULLIF(CONCAT(SUBSTRING(CAST(fv.sk_booking_created_date AS VARCHAR(8)), 1, 4), '-', SUBSTRING(CAST(fv.sk_booking_created_date AS VARCHAR(8)), 5, 2), '-', SUBSTRING(CAST(fv.sk_booking_created_date AS VARCHAR(8)), 7, 2)), -1)) AS dt_created,
    DATE(NULLIF(CONCAT(SUBSTRING(CAST(fv.sk_visit_completed_date AS VARCHAR(8)), 1, 4), '-', SUBSTRING(CAST(fv.sk_visit_completed_date AS VARCHAR(8)), 5, 2), '-', SUBSTRING(CAST(fv.sk_visit_completed_date AS VARCHAR(8)), 7, 2)), -1)) AS dt_completed,
    ROW_NUMBER() OVER (PARTITION BY fv.sk_booking ORDER BY COALESCE(hs.ts_updated,current_date) DESC ) AS order_booking
FROM
    dw_sale.fact_visits fv
JOIN dw_public.dim_region dr
    ON fv.sk_region = dr.sk_region
JOIN dw_public.dim_booking AS db
    ON db.sk_booking = fv.sk_booking
LEFT JOIN
	datalake_hub_services_clean.business_unit AS hs
		ON hs.id = fv.sk_business_unit
),
sale_bookings AS (
SELECT
    id_property,
    id_visitor,
    id_agent,
    sk_booking,
    sk_offer,
    is_hub_flow,
    hub_visit,
    city_group,
	is_3p_demand,
	demand_3p_partner,
    is_3p_supply,
	supply_3p_partner,
    dt_created,
    dt_completed,
    order_booking
FROM
    sale_bookings_base
WHERE
    order_booking =1
),
sale_closing AS (
    WITH fact_os AS (
    SELECT
        dd.date,
        sk_house,
        fo.sk_offer,
        fo.sk_buyer AS sk_buyer,
        fo.sk_agent AS id_agent,
        sdo.is_3p_demand,
        COALESCE(sdo.partner_3p_demand, '') AS partner_3p_demand,
        sdo.is_3p_supply,
        COALESCE(sdo.partner_3p_supply, '') AS partner_3p_supply,
        sdo.business_unit AS hub
    FROM
        dw_sale.fact_offers AS fo
    LEFT JOIN
        dw_public.dim_date AS dd
        ON dd.sk_date = fo.sk_offer_submitted_date
    INNER JOIN
        dw_sale.dim_offer AS sdo
        ON sdo.sk_offer = fo.sk_offer
    WHERE
        sk_offer_submitted_date > 0
    ),
    fact_oa AS (
    SELECT
        dd.date,
        sk_house,
        fo.sk_offer,
        fo.sk_buyer AS sk_buyer,
        fo.sk_agent AS id_agent,
        sdo.is_3p_demand,
        COALESCE(sdo.partner_3p_demand, '') AS partner_3p_demand,
        sdo.is_3p_supply,
        COALESCE(sdo.partner_3p_supply, '') AS partner_3p_supply,
        sdo.business_unit AS hub
    FROM
        dw_sale.fact_offers AS fo
    LEFT JOIN
        dw_public.dim_date AS dd
        ON dd.sk_date = fo.sk_offer_accepted_date
    INNER JOIN
        dw_sale.dim_offer AS sdo
        ON sdo.sk_offer = fo.sk_offer
    WHERE
        sk_offer_accepted_date > 0
    ),
    fact_ccv AS (
    SELECT
        dd.date,
        sk_house,
        fo.sk_offer,
        fo.sk_buyer AS sk_buyer,
        fo.sk_agent AS id_agent,
        sdo.is_3p_demand,
        COALESCE(sdo.partner_3p_demand, '') AS partner_3p_demand,
        sdo.is_3p_supply,
        COALESCE(sdo.partner_3p_supply, '') AS partner_3p_supply,
        sdo.business_unit AS hub
    FROM
        dw_sale.fact_offers fo
    LEFT JOIN
        dw_public.dim_date dd
        ON dd.sk_date = fo.sk_sale_agreement_signed_date
    INNER JOIN
        dw_sale.dim_offer sdo
        ON sdo.sk_offer = fo.sk_offer
    WHERE sk_sale_agreement_signed_date>0
    )
SELECT
    COALESCE(COALESCE(fact_os.sk_offer, fact_oa.sk_offer), fact_ccv.sk_offer) AS sk_offer,
    COALESCE(fact_os.sk_house,fact_oa.sk_house,fact_ccv.sk_house) AS sk_house,
    COALESCE(fact_os.sk_buyer,fact_oa.sk_buyer,fact_ccv.sk_buyer) AS sk_buyer,
    COALESCE(fact_os.id_agent,fact_oa.id_agent,fact_ccv.id_agent) AS id_agent,
    COALESCE(fact_os.is_3p_demand,fact_oa.is_3p_demand,fact_ccv.is_3p_demand) AS is_3p_demand,
    COALESCE(fact_os.partner_3p_demand,fact_oa.partner_3p_demand,fact_ccv.partner_3p_demand) AS demand_3p_partner,
    COALESCE(fact_os.is_3p_supply,fact_oa.is_3p_supply,fact_ccv.is_3p_supply) AS is_3p_supply,
    COALESCE(fact_os.partner_3p_supply,fact_oa.partner_3p_supply,fact_ccv.partner_3p_supply) AS supply_3p_partner,
    COALESCE(COALESCE(fact_os.hub, fact_oa.hub), fact_ccv.hub) AS hub_offer,
    MAX(fact_os.date) AS os_date,
    MAX(fact_oa.date) AS oa_date,
    MAX(fact_ccv.date) AS ccv_date
FROM
    fact_os
FULL OUTER JOIN
    fact_oa
        ON fact_os.sk_offer = fact_oa.sk_offer
FULL OUTER JOIN
    fact_ccv
        ON fact_os.sk_offer = fact_ccv.sk_offer
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9

),
sale_tta AS (
SELECT
	CAST(tta.house_id AS BIGINT) AS house_id,
	CAST(tta.tenant_id AS BIGINT) AS tenant_id,
	tta.agent_id AS id_agent,
	(tta.sk_house_listing || tta.tenant_id || tta.agent_id) AS tta_id,
	tta.first_message_ts,
	tta.first_attendance_ts
FROM
    datalake_talk_to_agent.talk_to_agent AS tta
WHERE
    tta.business_context = 'SALE'
),
sale_demand_region AS (
SELECT
	CAST(fsf.sk_house AS STRING) AS id_house,
    dr.city_group
FROM
    dw_sale.fact_sale_flows fsf
JOIN
    dw_public.dim_region dr
        ON dr.sk_region = fsf.sk_region
),
sale_demand_events AS (
SELECT
	COALESCE(offers.id_user, sc.sk_buyer, CAST(tta.tenant_id AS BIGINT)) AS id_buyer,
	COALESCE(offers.id_house, sc.sk_house, CAST(tta.house_id AS BIGINT), sc.sk_house) AS id_house,
	sc.id_agent AS id_agent, -- Using only sale_closing becaus monday's sk_agent is not trustworthy
    COALESCE(offers.is_3p_demand, sc.is_3p_demand, False) AS is_3p_demand,
    COALESCE(offers.demand_3p_partner, sc.demand_3p_partner) AS demand_3p_partner,
    COALESCE(offers.is_3p_supply, sc.is_3p_supply, False) AS is_3p_supply,
    COALESCE(offers.supply_3p_partner, sc.supply_3p_partner) AS supply_3p_partner,
	offers.form_of_payment,
	offers.dt_deal_qualified,
	sc.sk_offer AS id_offer,
    offers.dt_diligence_started_legaut,
    offers.dt_diligence_ended_legaut,
    offers.dt_diligence_ended,
    offers.dt_diligence_started_legal,
    offers.dt_diligence_ended_legal,
    offers.dt_credit_started,
    offers.dt_credit_approved,
    offers.dt_payment_concluded,
    offers.dt_notes_registry_started,
    offers.dt_notes_registry_ended,
    offers.dt_matricula_inicio,
    offers.dt_matricula_atualizada,
    offers.dt_entrega_chaves,
    offers.dt_finan_started,
    offers.dt_finan_ended,
	tta.tta_id,
	CAST(tta.first_message_ts AS TIMESTAMP) AS tta_started,
	CAST(tta.first_attendance_ts AS TIMESTAMP) AS tta_completed,
    sc.os_date,
    sc.oa_date,
    sc.ccv_date,
    sc.hub_offer
FROM
    sale_offers_adjusted AS offers
FULL OUTER JOIN
    sale_tta AS tta
        ON (offers.id_house = tta.house_id AND offers.id_user = tta.tenant_id)
FULL OUTER JOIN
	sale_closing AS sc
        ON offers.id_offer = sc.sk_offer
),

sale_demand_events_complete AS (
SELECT
    COALESCE(sde.id_buyer, db.id_visitor) AS id_buyer,
	COALESCE(sde.id_house, db.id_property) AS id_house,
    COALESCE(sde.id_agent, db.id_agent) AS id_agent,
    COALESCE(sde.is_3p_demand, db.is_3p_demand) AS is_3p_demand,
    COALESCE(sde.demand_3p_partner, db.demand_3p_partner) AS demand_3p_partner,
    COALESCE(sde.is_3p_supply, db.is_3p_supply) AS is_3p_supply,
    COALESCE(sde.supply_3p_partner, db.supply_3p_partner) AS supply_3p_partner,
	sde.id_offer,
    sde.form_of_payment,
    sde.os_date AS dt_offer_sent,
    sde.dt_deal_qualified,
    sde.oa_date AS dt_offer_accepted,
    sde.ccv_date AS dt_ccv_signed,
    sde.dt_diligence_started_legaut,
    sde.dt_diligence_ended_legaut,
    sde.dt_diligence_ended,
    sde.dt_diligence_started_legal,
    sde.dt_diligence_ended_legal,
    sde.dt_credit_started,
    sde.dt_credit_approved,
    sde.dt_payment_concluded,
    sde.dt_notes_registry_started,
    sde.dt_notes_registry_ended,
    sde.dt_matricula_inicio,
    sde.dt_matricula_atualizada,
    sde.dt_entrega_chaves,
    sde.dt_finan_started,
    sde.dt_finan_ended,
	sde.tta_id,
	sde.tta_started,
	sde.tta_completed,
    db.sk_booking,
    db.dt_created,
    db.dt_completed,
    db.city_group,
    db.hub_visit,
    sde.hub_offer
FROM
    sale_demand_events AS sde
FULL OUTER JOIN
    sale_bookings AS db
        ON (sde.id_house = db.id_property AND sde.id_buyer = db.id_visitor AND sde.id_offer = db.sk_offer )
),
sale_demand_classification AS (
SELECT
    sdc.id_buyer,
	sdc.id_house,
    CAST(sdc.is_3p_demand AS INT) AS is_3p_demand,
    NULLIF(sdc.demand_3p_partner, '') AS demand_3p_partner,
    CAST(sdc.is_3p_supply AS INT) AS is_3p_supply,
    NULLIF(sdc.supply_3p_partner, '') AS supply_3p_partner,
    CASE WHEN rbh.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3pbh_supply,
    rbh.partner AS supply_3pbh_partner,
    CASE
        WHEN COALESCE(sdr.city_group,sdc.city_group) NOT IN ('RMSP', 'Rio de Janeiro','Belo Horizonte','Porto Alegre','Campinas') THEN 'Out of coverage area'
        WHEN COALESCE(sdr.city_group,sdc.city_group) IN ('RMSP', 'Rio de Janeiro','Belo Horizonte','Porto Alegre','Campinas') THEN COALESCE(sdr.city_group,sdc.city_group)
    END AS city_group,
    sdc.form_of_payment,
	sdc.dt_offer_sent,
	sdc.dt_deal_qualified,
	sdc.dt_offer_accepted,
	sdc.dt_ccv_signed,
	sdc.id_offer,
	sdc.sk_booking,
	sdc.dt_created,
	sdc.dt_completed,
	sdc.tta_id,
	sdc.tta_started,
	sdc.tta_completed,
    sdc.dt_diligence_started_legaut,
    sdc.dt_diligence_ended_legaut,
    sdc.dt_diligence_ended,
    sdc.dt_diligence_started_legal,
    sdc.dt_diligence_ended_legal,
    sdc.dt_credit_started,
    sdc.dt_credit_approved,
    sdc.dt_payment_concluded,
    sdc.dt_notes_registry_started,
    sdc.dt_notes_registry_ended,
    sdc.dt_matricula_inicio,
    sdc.dt_matricula_atualizada,
    sdc.dt_entrega_chaves,
    sdc.dt_finan_started,
    sdc.dt_finan_ended,
    fsf.first_event AS first_touchpoint,
    fsf.higher_intent_before_offer,
    fsf.higher_intent_after_offer,
    sdc.hub_offer,
    sdc.hub_visit
FROM
    sale_demand_events_complete sdc
LEFT JOIN
	dw_sale.fact_sale_flows AS fsf
        ON sdc.id_buyer = CAST(fsf.sk_buyer AS STRING)
        AND sdc.id_house = CAST(fsf.sk_house AS STRING)
LEFT JOIN
    sale_demand_region sdr
        ON CAST(sdr.id_house AS STRING) = sdc.id_house
LEFT JOIN
    datalake_ebdb_listing.house AS rbh
    	ON rbh.id = sdc.id_house
			AND rbh.is_3p_supply_bh
),
lead_ AS (
SELECT
	slf.sk_lead_date AS base_date,
	slf.city_group,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
	slf.mkt_medium,
    slf.mkt_type,
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3pbh_supply,
    slf.supply_3pbh_partner,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0 AS is_3p_demand,
    slf.affiliate_volumetry,
    NULL AS demand_3p_partner,
	NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
    COUNT(slf.sk_lead_date) AS leads,
    NULL AS prospects,
    NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
	NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_lead_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
prospect AS (
SELECT
	slf.sk_prospect_date AS base_date,
	slf.city_group,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
	slf.mkt_medium,
    slf.mkt_type,
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3pbh_supply,
    slf.supply_3pbh_partner,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0 AS is_3p_demand,
	slf.affiliate_volumetry,
    NULL AS demand_3p_partner,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
    NULL AS leads,
    COUNT(slf.sk_prospect_date) AS prospects,
    NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
	NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
first_contacts AS (
SELECT
	slf.sk_prospect_date AS base_date,
	slf.city_group,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
	slf.mkt_medium,
    slf.mkt_type,
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3pbh_supply,
    slf.supply_3pbh_partner,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0 AS is_3p_demand,
	slf.affiliate_volumetry,
    NULL AS demand_3p_partner,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
    NULL AS leads,
    NULL AS prospects,
    COUNT(slf.sk_first_contact_date) AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
	NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_first_contact_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
qualified AS (
SELECT
    slf.sk_qualified_date AS base_date,
    slf.city_group,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
	slf.mkt_medium,
    slf.mkt_type,
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3pbh_supply,
    slf.supply_3pbh_partner,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0 AS is_3p_demand,
	slf.affiliate_volumetry,
    NULL AS demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
	NULL AS hub_offer,
    NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	COUNT(slf.sk_qualified_date) AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
	NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
available_qualified AS (
SELECT
    slf.sk_available_qualified_date AS base_date,
    slf.city_group,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
	slf.mkt_medium,
    slf.mkt_type,
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3pbh_supply,
    slf.supply_3pbh_partner,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0 AS is_3p_demand,
	slf.affiliate_volumetry,
    NULL AS demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
	NULL AS hub_offer,
    NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	COUNT(slf.sk_available_qualified_date) AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
	NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_available_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
opportunity AS (
SELECT
    slf.sk_opportunity_date AS base_date,
    slf.city_group,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
	slf.mkt_medium,
    slf.mkt_type,
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3pbh_supply,
    slf.supply_3pbh_partner,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0 AS is_3p_demand,
	slf.affiliate_volumetry,
    NULL AS demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
    NULL AS leads,
    NULL AS prospects,
    NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	COUNT(DISTINCT slf.sk_house_listing) AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
	NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_opportunity_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
first_listing AS (
SELECT
    slf.sk_first_listing_date AS base_date,
    slf.city_group,
    slf.lead_context,
    slf.mkt_campaign_context,
    slf.mkt_origin,
    slf.mkt_channel,
	slf.mkt_medium,
	slf.mkt_type,
	slf.sales_company,
	slf.lead_processing_operation,
    slf.is_3pbh_supply,
    slf.supply_3pbh_partner,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0 AS is_3p_demand,
	slf.affiliate_volumetry,
    NULL AS demand_3p_partner,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
    NULL AS leads,
    NULL AS prospects,
    NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	COUNT(DISTINCT slf.sk_house_listing) AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
	NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
    NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_first_listing_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
tta_sent AS (
SELECT
    CAST(REPLACE(DATE(tta_started),'-','') AS INT) AS base_date,
    city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
	NULL AS mkt_medium,
    NULL AS mkt_type,
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	COUNT(DISTINCT tta_id) AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification AS sdc
WHERE
    sdc.tta_started IS NOT NULL
--  DATE(tta_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
tta_completed AS (
SELECT
    CAST(REPLACE(DATE(tta_completed),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
	NULL AS mkt_medium,
    NULL AS mkt_type,
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	COUNT(DISTINCT tta_id) AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification AS sdc
WHERE
    sdc.tta_started IS NOT NULL
--  DATE(tta_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
visits_booked AS (
SELECT
	CAST(REPLACE(DATE(dt_created),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	COUNT(DISTINCT sk_booking) AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_created IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
order by 1 desc
),
visits_completed AS (
SELECT
	CAST(REPLACE(DATE(dt_completed),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
	NULL AS mkt_medium,
    NULL AS mkt_type,
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    COUNT(DISTINCT sk_booking) AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_completed IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
offers_sent AS (
SELECT
	CAST(REPLACE(DATE(dt_offer_sent),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
	NULL AS mkt_medium,
    NULL AS mkt_type,
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	COUNT(DISTINCT id_offer) AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_offer_sent IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
offers_deal_qualified AS (
SELECT
	CAST(REPLACE(DATE(dt_deal_qualified),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
	NULL AS mkt_medium,
    NULL AS mkt_type,
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	COUNT(DISTINCT id_offer) AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
	sale_demand_classification
WHERE
	dt_deal_qualified IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
offers_accepted AS (
SELECT
	CAST(REPLACE(DATE(dt_offer_accepted),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
    NULL AS mkt_channel,
	NULL AS mkt_medium,
    NULL AS mkt_type,
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	COUNT(DISTINCT id_offer) AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_offer_accepted IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
ccv_signed AS (
SELECT
	CAST(REPLACE(DATE(dt_ccv_signed),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	COUNT(DISTINCT id_offer) AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_ccv_signed IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
diligence_started_legaut AS (
SELECT
	CAST(REPLACE(DATE(dt_diligence_started_legaut),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	COUNT(DISTINCT id_offer) AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_diligence_started_legaut IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
diligence_ended_legaut AS (
SELECT
	CAST(REPLACE(DATE(dt_diligence_ended_legaut),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	COUNT(DISTINCT id_offer) AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_diligence_ended_legaut IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
diligence_ended AS (
SELECT
	CAST(REPLACE(DATE(dt_diligence_ended),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	COUNT(DISTINCT id_offer) AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_diligence_ended IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
diligence_started_legal AS (
SELECT
	CAST(REPLACE(DATE(dt_diligence_started_legal),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	COUNT(DISTINCT id_offer) AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_diligence_started_legal IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
diligence_ended_legal AS (
SELECT
	CAST(REPLACE(DATE(dt_diligence_ended_legal),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	COUNT(DISTINCT id_offer) AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_diligence_ended_legal IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
credit_sent AS (
SELECT
	CAST(REPLACE(DATE(dt_credit_started),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	COUNT(DISTINCT id_offer) AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_credit_started IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
credit_approved AS (
SELECT
	CAST(REPLACE(DATE(dt_credit_approved),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	COUNT(DISTINCT id_offer) AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_credit_approved IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
finan_started AS (
SELECT
	CAST(REPLACE(DATE(dt_finan_started),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	COUNT(DISTINCT id_offer) AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_finan_started IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
finan_ended AS (
SELECT
	CAST(REPLACE(DATE(dt_finan_ended),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	COUNT(DISTINCT id_offer) AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_finan_ended IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
payment_concluded AS (
SELECT
	CAST(REPLACE(DATE(dt_payment_concluded),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	COUNT(DISTINCT id_offer) AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_payment_concluded IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
notes_registry_started AS (
SELECT
	CAST(REPLACE(DATE(dt_notes_registry_started),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	COUNT(DISTINCT id_offer) AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
	sale_demand_classification
WHERE
	dt_notes_registry_started IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
notes_registry_ended AS (
SELECT
	CAST(REPLACE(DATE(dt_notes_registry_ended),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	COUNT(DISTINCT id_offer) AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
	sale_demand_classification
WHERE
	dt_notes_registry_ended IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
matricula_inicio AS (
SELECT
	CAST(REPLACE(DATE(dt_matricula_inicio),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	COUNT(DISTINCT id_offer) AS matricula_inicio,
	NULL AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_matricula_inicio IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
matricula_atualizada AS (
SELECT
	CAST(REPLACE(DATE(dt_matricula_atualizada),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
    NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	COUNT(DISTINCT id_offer) AS matricula_atualizada,
	NULL AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_matricula_atualizada IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
),
entrega_chave AS (
SELECT
	CAST(REPLACE(DATE(dt_entrega_chaves),'-','') AS INT) AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_medium,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
    is_3pbh_supply,
    supply_3pbh_partner,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
	NULL AS affiliate_volumetry,
    demand_3p_partner,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
	NULL AS leads,
	NULL AS prospects,
	NULL AS first_contacts,
	NULL AS qualifieds,
	NULL AS available_qualifieds,
	NULL AS opportunities,
	NULL AS first_listings,
	NULL AS tta_started,
	NULL AS tta_completed,
	NULL AS visits_booked,
   	NULL AS visits_completed,
	NULL AS offers_submitted,
	NULL AS deal_qualified,
	NULL AS offers_accepted,
	NULL AS ccv_signed,
	NULL AS diligence_started_legaut,
	NULL AS diligence_ended_legaut,
	NULL AS diligence_ended,
	NULL AS diligence_started_legal,
	NULL AS diligence_ended_legal,
	NULL AS credit_sent,
	NULL AS credit_approved,
	NULL AS finan_started,
	NULL AS finan_ended,
	NULL AS payment_concluded,
	NULL AS notes_registry_started,
	NULL AS notes_registry_ended,
	NULL AS matricula_inicio,
	NULL AS matricula_atualizada,
	COUNT(DISTINCT id_offer) AS entrega_chave
FROM
    sale_demand_classification
WHERE
    dt_entrega_chaves IS NOT NULL
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
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
	SELECT * FROM available_qualified
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
	SELECT * FROM notes_registry_started
	UNION ALL
	SELECT * FROM notes_registry_ended
	UNION ALL
	SELECT * FROM matricula_inicio
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
    ua.is_3pbh_supply,
    ua.supply_3pbh_partner,
    ua.is_3p_supply,
    ua.supply_3p_partner,
    ua.is_3p_demand,
    ua.demand_3p_partner,
	ua.lead_context,
	ua.mkt_campaign_context,
	ua.mkt_origin,
	ua.mkt_channel,
	ua.mkt_medium,
	ua.mkt_type,
	ua.sales_company,
    ua.lead_processing_operation,
	ua.affiliate_volumetry,
	ua.first_origin_demand,
	ua.origin_before_offer,
	ua.origin_after_offer,
	ua.form_of_payment,
	ua.hub_visit,
	ua.hub_offer,
	ua.leads,
	ua.prospects,
	ua.first_contacts,
	ua.qualifieds,
	ua.available_qualifieds,
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
	ua.notes_registry_started,
	ua.notes_registry_ended,
	ua.matricula_inicio,
	ua.matricula_atualizada,
	ua.entrega_chave
FROM
    union_all ua
RIGHT JOIN
    dw_public.dim_date dd
        ON ua.base_date = dd.sk_date
WHERE
    dd.date BETWEEN '2020-01-01' AND current_date
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
	mkt_medium,
	mkt_type,
	sales_company,
	lead_processing_operation,
	affiliate_volumetry,
	first_origin_demand,
	origin_before_offer,
	origin_after_offer,
	form_of_payment,
	hub_visit,
	hub_offer,
    supply_3p_partner,
    demand_3p_partner,
    supply_3pbh_partner,
    is_3p_supply,
    is_3p_demand,
    is_3pbh_supply,
	SUM(leads) AS leads,
    SUM(prospects) AS prospects,
    SUM(first_contacts) AS first_contacts,
	SUM(qualifieds) AS qualifieds,
	SUM(available_qualifieds) AS available_qualifieds,
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
	SUM(notes_registry_started) AS notes_registry_started,
	SUM(notes_registry_ended) AS notes_registry_ended,
	SUM(matricula_inicio) AS matricula_inicio,
	SUM(matricula_atualizada) AS matricula_atualizada,
	SUM(entrega_chave) AS entrega_chave,
	current_timestamp AS ts_load
FROM
    union_all_date
GROUP BY
    week_start,
	date,
	month,
	quarter,
	city_group,
	lead_context,
	mkt_campaign_context,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_type,
	sales_company,
	lead_processing_operation,
	affiliate_volumetry,
	first_origin_demand,
	origin_before_offer,
	origin_after_offer,
	form_of_payment,
	hub_visit,
	hub_offer,
    is_3pbh_supply,
    supply_3p_partner,
    demand_3p_partner,
    supply_3pbh_partner,
    is_3p_supply,
    is_3p_demand
