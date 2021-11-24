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
	lf.sales_company,
	CASE
	    WHEN lf.mkt_origin = 'B2B' OR lf.mkt_origin = 'CIQ' THEN lf.mkt_origin
	    WHEN lf.mkt_completion = 'Full Self-Service' THEN 'FSS'
	    ELSE 'IS'
	END AS lead_context,
	CASE
    	    WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other') AND lead_context IN ('FSS','IS') THEN 'IS'
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
	END AS city_group
FROM
    datamarts.lead_listing_flows lf
LEFT JOIN
    dim_region dr
        ON dr.sk_region = lf.sk_region
WHERE lf.origin_table = 'Sale'
),
monday_adjusted AS (
-- data from datalake_firestore_prod.monday
SELECT
	mo.id_offer,
	mo.id_buyer||'_'||mo.id_house AS sale_flow,
	mo.id_house,
	mo.id_buyer AS id_user,
	CASE
	    WHEN mo.payment_method IN ('1', '7') THEN 'Financiado'
	    WHEN mo.payment_method = '2' THEN 'À Vista'
	    WHEN mo.payment_method = '3' THEN 'À Vista + FGTS'
	    WHEN mo.payment_method = '4' THEN 'Financiado + FGTS'
	ELSE 'Other'END AS form_of_payment,
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
	mo.dt_notes_registry_started AS dt_notes_registry_started,
	mo.dt_notes_registry_ended AS dt_notes_registry_ended,
	mo.dt_house_registry_started AS dt_matricula_inicio,
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
sale_bookings AS (
SELECT
	fv.sk_house AS id_property,
	fv.sk_buyer AS id_visitor,
	fv.sk_offer,
	fv.sk_booking,
	fv.is_hub_flow,
	CASE
        when is_hub_flow = true AND dr.sk_region in (55, 56, 70, 72, 1329) and date(sk_booking_created_date) between  '2021-04-26' and current_date then 'HUB BELA VISTA'
        when is_hub_flow = true AND dr.sk_region in (1577,54) and  date(sk_booking_created_date) between '2021-08-15' and current_date then 'HUB BELA VISTA' -- Liberdade, Centro
        when is_hub_flow = true AND dr.sk_region in (51, 1281, 1287, 52, 1298, 1300) and date(sk_booking_created_date) between '2021-04-26'and current_date then 'HUB VILA MARIANA'
        when is_hub_flow = true AND dr.sk_region in (1298,1300) and date(sk_booking_created_date) >= '2021-08-15' then 'HUB VILA MARIANA'  -- Cambuci, Ipiranga
        when is_hub_flow = true AND dr.sk_region in (73,1284,1299,69,1286,1285,65,1283,1282,64,68,71) and date(sk_booking_created_date) between '2021-06-18' and current_date then 'HUB PERDIZES'
        when is_hub_flow = true AND dr.sk_region in (61,2345,62,2341,63,46,45,58,47,57,60,59) and date(sk_booking_created_date) between '2021-08-15' and current_date then 'HUB VILA MADALENA'
        when is_hub_flow = true AND dr.sk_region in (2667,2664,1589,2148,1306,1305,1303,1301,2666,2165,1304,2674,1588,1302,2159,1583) and date(sk_booking_created_date) between '2021-10-04' and current_date then 'HUB TATUAPÉ'
        when is_hub_flow = true AND dr.sk_region in (1302, 1303, 1304, 1305, 1306, 2148, 2165) and date(sk_booking_created_date) between '2021-10-13' and current_date then 'HUB TATUAPÉ'
        when is_hub_flow = true AND dr.sk_region in (1587,1311,1584,1312,2541,1800,1655,1310,2543,1579,1915) and date(sk_booking_created_date) between '2021-10-04' and current_date then 'HUB SANTANA'
        when is_hub_flow = true AND dr.sk_region in (1310, 1311, 1655, 2541, 2543) and date(sk_booking_created_date) between '2021-10-13' and current_date then 'HUB SANTANA'
        when is_hub_flow = true AND dr.sk_region in (2164,2153,1344,1476,2347,1343,1797,2487,1477,1479,2157,2162,2143,1478,1347,1798) and date(sk_booking_created_date) between '2021-10-18' and current_date then 'HUB BUTANTÃ'
        when is_hub_flow = true AND dr.sk_region in (43,2423,44,1581,1280,2425,42,1585,2424,2422) and date(sk_booking_created_date) between '2021-10-18'  and current_date then 'HUB BROOKLIN'
        when is_hub_flow = true AND dr.sk_region IN (1873, 1874, 1875, 1879, 1881, 1882, 1883, 1885, 1886, 1888, 1892, 1893, 1894, 1896, 1898, 1899, 1900, 1901, 1903, 1907, 1908, 1909, 1911) and
            date(sk_booking_created_date) between '2021-10-20' and current_date then 'HUB PORTO ALEGRE'
        when is_hub_flow = true AND dr.sk_region IN (1880, 1884, 1890, 1891, 1895, 1897, 1902, 1910, 1996, 1998, 1999, 2336, 2337, 2659, 2680, 2681, 5162) and  date(sk_booking_created_date) between '2021-10-20' and current_date then 'HUB PORTO ALEGRE'
        when is_hub_flow = true AND dr.sk_region IN (1876, 1877, 1878, 1887, 1889, 1904, 1905, 1906, 1994, 1995, 1997, 2000, 2661, 2662, 2678, 2679, 3923, 3924) and date(sk_booking_created_date) between '2021-10-20' and current_date then 'HUB PORTO ALEGRE'
        when is_hub_flow = true AND dr.sk_region IN (2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2022, 2023, 2024, 2026, 2027, 2028, 2029, 2030, 2031, 2032, 2033, 2034, 2035, 2036,
            2268, 2269, 2270, 2271, 2272, 2273, 2274, 2275, 2301, 2302, 2303, 2427, 2433, 2446, 2447, 2498, 2499, 2500, 2639, 2640, 2641, 2642, 2682, 2683, 2684, 2685, 2686, 2687, 2688, 3918)
            and date(sk_booking_created_date) between '2021-10-20' and current_date then 'HUB PORTO ALEGRE'
        when is_hub_flow = true AND dr.region_code in ('SPO 01', 'SPO 06') and date(sk_booking_created_date) between '2021-04-13' and current_date then 'Lite 1'
        when is_hub_flow = true AND dr.region_code in ('SPO 08', 'STA 01', 'SCA 01','SBE 01', 'DIA 01') and date(sk_booking_created_date) between '2021-05-04' and current_date then 'Lite 2'
        when is_hub_flow = true AND dr.region_code in ('RIO 06','RIO 07','RIO 09') and  date(sk_booking_created_date) between '2021-09-13' and current_date then 'Lite Rio'
        when is_hub_flow = true AND dr.region_code in ('RIO 01','RIO 02','RIO 03') and date(sk_booking_created_date) between '2021-09-13' and  '2021-10-24'then 'Lite Rio'
        when is_hub_flow = true AND dr.city_group = 'Porto Alegre' and  date(sk_booking_created_date) between '2021-07-05' and '2021-11-10' then 'Lite POA'
        when is_hub_flow = true AND dr.city_group = 'Porto Alegre' and date(sk_booking_created_date) between '2021-11-10' and current_date then 'HUB PORTO ALEGRE'
        when is_hub_flow = true AND dr.region_code in ('RIO 01','RIO 02','RIO 03') and date(sk_booking_created_date) between '2021-11-17' and current_date then 'HUB RJ ZONA SUL'
    END AS hub_visit,
	dr.city_group,
	DATE(NULLIF(fv.sk_booking_created_date,-1)) AS dt_created,
	DATE(NULLIF(fv.sk_visit_completed_date,-1)) AS dt_completed
FROM
    sale.fact_visits fv
JOIN dim_region dr
    ON fv.sk_region = dr.sk_region
),
sale_closing AS (
    WITH fact_os AS (
    SELECT
        dd.date,
        sk_house,
        fo.sk_offer,
        fo.sk_buyer AS sk_buyer,
        business_unit AS hub
    FROM
    	datamarts.temp_sale_offers fo
    LEFT JOIN
        dim_date dd
        ON dd.sk_date = fo.sk_offer_submitted_date
    WHERE
    	sk_offer_submitted_date > 0
    ),
    fact_oa AS (
    SELECT
        dd.date,
        sk_house,
        fo.sk_offer,
        fo.sk_buyer AS sk_buyer,
        business_unit AS hub
    FROM
    	datamarts.temp_sale_offers fo
    LEFT JOIN
        dim_date dd
        ON dd.sk_date = fo.sk_offer_accepted_date
    WHERE
        sk_offer_accepted_date > 0
    ),
    fact_ccv AS (
    SELECT
        dd.date,
        sk_house,
        fo.sk_offer,
        fo.sk_buyer AS sk_buyer,
        business_unit AS hub
    FROM
    	datamarts.temp_sale_offers fo
    LEFT JOIN
        dim_date dd
        ON dd.sk_date = fo.sk_sale_agreement_signed_date
    WHERE sk_sale_agreement_signed_date>0
    )
SELECT
    COALESCE(COALESCE(fact_os.sk_offer, fact_oa.sk_offer), fact_ccv.sk_offer) AS sk_offer,
    COALESCE(fact_os.sk_house,fact_oa.sk_house,fact_ccv.sk_house) AS sk_house,
    COALESCE(fact_os.sk_buyer,fact_oa.sk_buyer,fact_ccv.sk_buyer) AS sk_buyer,
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
GROUP BY 1, 2, 3, 4

),
sale_tta AS (
SELECT
	tta.house_id::BIGINT AS house_id,
	tta.tenant_id::BIGINT AS tenant_id,
	(tta.sk_house_listing || tta.tenant_id || tta.agent_id) AS tta_id,
	tta.first_message_ts,
	tta.first_attendance_ts
FROM
    datamarts.talk_to_agent tta
WHERE
    tta.business_context = 'SALE'
),
sale_demand_region AS (
SELECT
	fsf.sk_house::VARCHAR AS id_house,
	dr.city_group
FROM
    sale.fact_sale_flows fsf
JOIN
    dim_region dr
        ON dr.sk_region = fsf.sk_region
),
sale_demand_events AS (
SELECT
	COALESCE(offers.id_user, sc.sk_buyer, tta.tenant_id::BIGINT) AS id_buyer,
	COALESCE(offers.id_house, sc.sk_house, tta.house_id::BIGINT, sc.sk_house) AS id_house,
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
	tta.first_message_ts::TIMESTAMP AS tta_started,
	tta.first_attendance_ts::TIMESTAMP AS tta_completed,
	sc.os_date,
	sc.oa_date,
	sc.ccv_date,
	sc.hub_offer
FROM
    monday_adjusted offers
FULL OUTER JOIN
    sale_tta tta
        ON (offers.id_house = tta.house_id AND offers.id_user = tta.tenant_id)
FULL OUTER JOIN
	sale_closing AS sc
		ON offers.id_offer = sc.sk_offer
),

sale_demand_events_complete AS (
SELECT
    COALESCE(sde.id_buyer, db.id_visitor) AS id_buyer,
	COALESCE(sde.id_house, db.id_property) AS id_house,
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
    sale_demand_events sde
FULL OUTER JOIN
    sale_bookings db
        ON (sde.id_house = db.id_property AND sde.id_buyer = db.id_visitor AND sde.id_offer = db.sk_offer )
),
sale_demand_classification AS (
SELECT
    sdc.id_buyer,
	sdc.id_house,
	CASE
	    WHEN COALESCE(sdr.city_group,sdc.city_group) NOT IN ('RMSP', 'Rio de Janeiro','Porto Alegre','Campinas') THEN 'Out of coverage area'
	    WHEN COALESCE(sdr.city_group,sdc.city_group) IN ('RMSP', 'Rio de Janeiro','Porto Alegre','Campinas') THEN COALESCE(sdr.city_group,sdc.city_group)
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
	sale.fact_sale_flows AS fsf
		ON sdc.id_buyer = fsf.sk_buyer::VARCHAR
		AND sdc.id_house = fsf.sk_house::VARCHAR
LEFT JOIN
    sale_demand_region sdr
        ON sdr.id_house::VARCHAR = sdc.id_house
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
    slf.sales_company,
    slf.lead_processing_operation,
	NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_lead_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    slf.sales_company,
    slf.lead_processing_operation,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    slf.sales_company,
    slf.lead_processing_operation,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_first_contact_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    slf.sales_company,
    slf.lead_processing_operation,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
	NULL AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    slf.sales_company,
    slf.lead_processing_operation,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_opportunity_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	slf.sales_company,
	slf.lead_processing_operation,
    NULL AS first_origin_demand,
	NULL AS origin_before_offer,
	NULL AS origin_after_offer,
	NULL AS form_of_payment,
	NULL AS hub_visit,
	NULL AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_first_listing_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(tta_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(tta_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
order by 1 desc
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_completed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
	sale_demand_classification
WHERE
	DATE(dt_deal_qualified) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_offer_accepted) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_started_legaut) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_ended_legaut) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_ended) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_started_legal) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_ended_legal) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_credit_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_credit_approved) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_finan_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_finan_ended) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_payment_concluded) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
),
notes_registry_started AS (
SELECT
	REPLACE(DATE(dt_notes_registry_started),'-','')::INTEGER AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	COUNT(DISTINCT id_offer) AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
	sale_demand_classification
WHERE
	DATE(dt_notes_registry_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	COUNT(DISTINCT id_offer) AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
	sale_demand_classification
WHERE
	DATE(dt_notes_registry_ended) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
),
matricula_inicio AS (
SELECT
	REPLACE(DATE(dt_matricula_inicio),'-','')::INTEGER AS base_date,
	city_group,
	NULL AS lead_context,
    NULL AS mkt_campaign_context,
    NULL AS mkt_origin,
	NULL AS mkt_channel,
	NULL AS mkt_type,
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	COUNT(DISTINCT id_offer) AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_matricula_inicio) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	COUNT(DISTINCT id_offer) AS matricula_atualizada,
	NULL::BIGINT AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_matricula_atualizada) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	NULL AS sales_company,
	NULL AS lead_processing_operation,
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	form_of_payment,
	hub_visit AS hub_visit,
	hub_offer AS hub_offer,
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
	NULL::BIGINT AS notes_registry_started,
	NULL::BIGINT AS notes_registry_ended,
	NULL::BIGINT AS matricula_inicio,
	NULL::BIGINT AS matricula_atualizada,
	COUNT(DISTINCT id_offer) AS entrega_chave
FROM
    sale_demand_classification
WHERE
    DATE(dt_entrega_chaves) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
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
	ua.lead_context,
	ua.mkt_campaign_context,
	ua.mkt_origin,
	ua.mkt_channel,
	ua.mkt_type,
	ua.sales_company,
    ua.lead_processing_operation,
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
    dim_date dd
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
	mkt_type,
	sales_company,
	lead_processing_operation,
	first_origin_demand,
	origin_before_offer,
	origin_after_offer,
	form_of_payment,
	hub_visit,
	hub_offer,
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
	 mkt_type,
	 sales_company,
	 lead_processing_operation,
	 first_origin_demand,
	 origin_before_offer,
	 origin_after_offer,
	 form_of_payment,
	 hub_visit,
	 hub_offer
ORDER BY 1 desc