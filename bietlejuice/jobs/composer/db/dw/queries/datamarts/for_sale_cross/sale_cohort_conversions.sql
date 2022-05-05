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
    CASE WHEN hp.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
    hp.partner AS supply_3p_partner,
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
LEFT JOIN
    datalake_3p_prod.houses_3p AS hp
    ON hp.id_house = lf.sk_house_listing / 1000 
WHERE lf.origin_table = 'Sale'
),
agents_3p AS (
    SELECT
        ac.id_agent,
        ac.id_user_agent,
        ac.id_work_contract,
        ac.ts_work_contract_started,
        ac.ts_work_contract_ended,
        NULLIF(wc."3p_partner", '') AS demand_3p_partner,
        wc.is_3p_contract
    FROM
        datalake_ebdb_agents_prod.agent_contract AS ac
    JOIN datalake_ebdb_work_contract_prod.work_contract AS wc
        ON ac.id_work_contract = wc.id
),
monday_adjusted AS (
-- data from datalake_firestore_prod.monday
SELECT
    mo.id_offer,
    mo.id_buyer||'_'||mo.id_house AS sale_flow,
    mo.id_house,
    mo.id_buyer AS id_user,
    mo.id_agent,
    CASE
        WHEN mo.payment_method IN ('1', '7') THEN 'Financiado'
        WHEN mo.payment_method = '2' THEN 'À Vista'
        WHEN mo.payment_method = '3' THEN 'À Vista + FGTS'
        WHEN mo.payment_method = '4' THEN 'Financiado + FGTS'
	END AS form_of_payment,
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
sale_bookings_base AS (
SELECT
    fv.sk_house AS id_property,
    fv.sk_buyer AS id_visitor,
    fv.sk_agent AS id_agent,
    fv.sk_offer,
    fv.sk_booking,
    fv.is_hub_flow,
	bur.business_unit AS hub_visit,
    dr.city_group,
	COALESCE(ap.is_3p_contract, FALSE) AS is_3p_demand,
	ap.demand_3p_partner,
    DATE(NULLIF(fv.sk_booking_created_date,-1)) AS dt_created,
    DATE(NULLIF(fv.sk_visit_completed_date,-1)) AS dt_completed,
    ROW_NUMBER() OVER (PARTITION BY fv.sk_booking ORDER BY COALESCE(bur.dt_coverage_ended,current_date) DESC ) AS order_booking
FROM
    sale.fact_visits fv
JOIN dim_region dr
    ON fv.sk_region = dr.sk_region
JOIN dim_booking AS db
    ON db.sk_booking = fv.sk_booking
LEFT JOIN
     sale.fact_business_unit_region bur
    ON bur.sk_region = fv.sk_region
    AND DATE(fv.sk_booking_created_date) BETWEEN DATE (bur.dt_coverage_started) 
    AND DATE(COALESCE(bur.dt_coverage_ended, current_date))
LEFT JOIN
	agents_3p AS ap
	ON ap.id_agent = db.id_agent
    AND db.dt_created BETWEEN ap.ts_work_contract_started AND COALESCE(ts_work_contract_ended, db.ts_load)
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
        sdo.business_unit AS hub
    FROM
        sale.fact_offers fo
    LEFT JOIN
        dim_date dd
        ON dd.sk_date = fo.sk_offer_submitted_date
    INNER JOIN 
        sale.dim_offer sdo
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
        sdo.business_unit AS hub
    FROM
        sale.fact_offers fo
    LEFT JOIN
        dim_date dd
        ON dd.sk_date = fo.sk_offer_accepted_date
    INNER JOIN 
        sale.dim_offer sdo
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
        sdo.business_unit AS hub
    FROM
        sale.fact_offers fo
    LEFT JOIN
        dim_date dd
        ON dd.sk_date = fo.sk_sale_agreement_signed_date
    INNER JOIN 
        sale.dim_offer sdo
        ON sdo.sk_offer = fo.sk_offer
    WHERE sk_sale_agreement_signed_date>0
    )
SELECT
    COALESCE(COALESCE(fact_os.sk_offer, fact_oa.sk_offer), fact_ccv.sk_offer) AS sk_offer,
    COALESCE(fact_os.sk_house,fact_oa.sk_house,fact_ccv.sk_house) AS sk_house,
    COALESCE(fact_os.sk_buyer,fact_oa.sk_buyer,fact_ccv.sk_buyer) AS sk_buyer,
    COALESCE(fact_os.id_agent,fact_oa.id_agent,fact_ccv.id_agent) AS id_agent,
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
GROUP BY 1, 2, 3, 4, 5
),
sale_demand_region AS (
SELECT
    fsf.sk_house:: VARCHAR AS id_house,
    dr.city_group
FROM
    sale.fact_sale_flows fsf
JOIN
    dim_region dr
        ON dr.sk_region = fsf.sk_region
),
sale_demand_events AS (
SELECT
    COALESCE(offers.id_user, sc.sk_buyer) AS id_buyer,
    COALESCE(offers.id_house, sc.sk_house) AS id_house,
    sc.id_agent AS id_agent, -- Using only sale_closing becaus monday's sk_agent is not trustworthy
    sc.sk_offer AS id_offer,
    offers.form_of_payment,
    offers.dt_offer_sent,
    offers.dt_deal_qualified,
    offers.dt_offer_accepted,
    offers.dt_ccv_signed,
    offers.dt_diligence_started_legaut,
    offers.dt_diligence_ended_legaut,
    offers.dt_diligence_ended,
    offers.dt_diligence_started_legal,
    offers.dt_diligence_ended_legal,
    offers.dt_offer_rejected,
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
    sc.os_date,
    sc.oa_date,
    sc.ccv_date,
    sc.hub_offer
FROM
    monday_adjusted offers
FULL OUTER JOIN
    sale_closing sc
        ON offers.id_offer = sc.sk_offer
),
sale_demand_events_complete AS (
SELECT
    COALESCE(sde.id_buyer, db.id_visitor) AS id_buyer,
	COALESCE(sde.id_house, db.id_property) AS id_house,
    COALESCE(sde.id_agent, db.id_agent) AS id_agent,
	COALESCE(db.is_3p_demand, FALSE) AS is_3p_demand,
	db.demand_3p_partner,
    sde.form_of_payment,
    sde.os_date AS dt_offer_sent,
    sde.dt_deal_qualified,
    sde.oa_date AS dt_offer_accepted,
    sde.ccv_date AS dt_ccv_signed,
    sde.dt_offer_rejected,
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
    sde.id_offer,
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
        ON (sde.id_house = db.id_property AND sde.id_buyer = db.id_visitor AND sde.id_offer = db.sk_offer)
),
sale_demand_classification AS (
SELECT
    sdc.id_offer,
    sdc.sk_booking,
    sdc.id_buyer,
    sdc.id_house,
    sdc.is_3p_demand::INT,
    sdc.demand_3p_partner,
    CASE WHEN hp.id_house IS NOT NULL THEN 1 ELSE 0 END AS is_3p_supply,
    hp.partner AS supply_3p_partner,
    CASE
        WHEN COALESCE(sdr.city_group,sdc.city_group) NOT IN ('RMSP', 'Rio de Janeiro','Porto Alegre','Campinas') THEN 'Out of coverage area'
        WHEN COALESCE(sdr.city_group,sdc.city_group) IN ('RMSP', 'Rio de Janeiro','Porto Alegre','Campinas') THEN COALESCE(sdr.city_group,sdc.city_group)
    END AS city_group,
    sdc.form_of_payment,
    sdc.dt_created,
    sdc.dt_completed,
    sdc.dt_offer_sent,
    sdc.dt_deal_qualified,
    sdc.dt_offer_accepted,
    sdc.dt_ccv_signed,
    sdc.dt_offer_rejected,
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
    sale.fact_sale_flows fsf
        ON sdc.id_buyer = fsf.sk_buyer::VARCHAR
        AND sdc.id_house = fsf.sk_house::VARCHAR
LEFT JOIN
    sale_demand_region sdr
        ON sdr.id_house::VARCHAR = sdc.id_house
LEFT JOIN
    datalake_3p_prod.houses_3p AS hp
    ON hp.id_house = sdc.id_house
-- LEFT JOIN
--     payment_method_adjusted pma
--         ON pma.id = sdc.id_offer
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
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0::INT AS is_3p_demand,
    NULL::VARCHAR AS demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
    NULL AS hub_offer,
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
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0::INT AS is_3p_demand,
    NULL::VARCHAR AS demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
    NULL AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_contact_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_contact_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1))))
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_contact_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    COUNT(slf.sk_first_contact_date) AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_first_contact_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0::INT AS is_3p_demand,
    NULL::VARCHAR AS demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
    NULL AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1))))
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_prospect_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_qualified_date,-1)))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    COUNT(slf.sk_prospect_date) AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0::INT AS is_3p_demand,
    NULL::VARCHAR AS demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
    NULL AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1)))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1))))
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_qualified_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_opportunity_date,-1)))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    COUNT(slf.sk_qualified_date) AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    slf.sales_company,
    slf.lead_processing_operation,
    slf.is_3p_supply,
    slf.supply_3p_partner,
    0::INT AS is_3p_demand,
    NULL::VARCHAR AS demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
    NULL AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1)))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1))))
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_opportunity_date)),DATE_TRUNC('week',DATE(NULLIF(slf.sk_first_listing_date,-1)))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    COUNT(DISTINCT slf.sk_house_listing) AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_opportunity_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
fl2ccv AS (
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
    slf.is_3p_supply,
    slf.supply_3p_partner,
    sde.is_3p_demand,
    sde.demand_3p_partner,
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
    NULL AS hub_visit,
    NULL AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_listing_date)),DATE_TRUNC('week',DATE(NULLIF(sde.dt_ccv_signed,-1)))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_listing_date)),DATE_TRUNC('week',DATE(NULLIF(sde.dt_ccv_signed,-1))))
        WHEN datediff('week',DATE_TRUNC('week',DATE(slf.sk_first_listing_date)),DATE_TRUNC('week',DATE(NULLIF(sde.dt_ccv_signed,-1)))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    COUNT(DISTINCT slf.sk_house_listing) as fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
LEFT JOIN
    sale_demand_classification sde
        ON sde.id_house = slf.sk_house_listing/1000
WHERE
    slf.sk_first_listing_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_completed))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    COUNT(DISTINCT sk_booking) AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent))) < 20
                THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent)))
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_sent))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    COUNT(DISTINCT sk_booking) AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
vb2oa AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_accepted))) < 20
                THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_accepted)))
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_offer_accepted))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    COUNT(DISTINCT sk_booking) AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
vb2ccv AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_ccv_signed))) < 20
                THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_ccv_signed)))
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_created)),DATE_TRUNC('week',DATE(dt_ccv_signed))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    COUNT(DISTINCT sk_booking) AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
vc2ccv AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_ccv_signed))) < 20
                THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_ccv_signed)))
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_ccv_signed))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    COUNT(DISTINCT sk_booking) AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_completed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_sent))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    COUNT(DISTINCT sk_booking) AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_completed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
vc2oa AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_accepted))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_accepted)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_completed)),DATE_TRUNC('week',DATE(dt_offer_accepted))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    COUNT(DISTINCT sk_booking) AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_completed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted))) < 20
                THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_offer_accepted))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    COUNT(DISTINCT id_offer) AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
os2dq AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_deal_qualified))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_deal_qualified)))
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_deal_qualified))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    COUNT(DISTINCT id_offer) AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
dq2oa AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_deal_qualified)),DATE_TRUNC('week',DATE(dt_offer_accepted))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_deal_qualified)),DATE_TRUNC('week',DATE(dt_offer_accepted)))
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_deal_qualified)),DATE_TRUNC('week',DATE(dt_offer_accepted))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT  AS os2dq,
    COUNT(DISTINCT id_offer)AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_deal_qualified) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
os2ccv AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_ccv_signed))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_ccv_signed)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_sent)),DATE_TRUNC('week',DATE(dt_ccv_signed))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    COUNT(DISTINCT id_offer) AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_offer_accepted)),DATE_TRUNC('week',DATE(dt_ccv_signed))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    COUNT(DISTINCT id_offer) AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_offer_accepted) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
ccv2lts AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_diligence_started_legaut))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_diligence_started_legaut)))
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_diligence_started_legaut))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    COUNT(DISTINCT id_offer) AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
lts2lte AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_diligence_started_legaut)),DATE_TRUNC('week',DATE(dt_diligence_ended_legaut))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_diligence_started_legaut)),DATE_TRUNC('week',DATE(dt_diligence_ended_legaut)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_diligence_started_legaut)),DATE_TRUNC('week',DATE(dt_diligence_ended_legaut))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    COUNT(DISTINCT id_offer) AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_started_legaut) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
lte2lrs AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_diligence_ended_legaut)),DATE_TRUNC('week',DATE(dt_diligence_started_legal))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_diligence_ended_legaut)),DATE_TRUNC('week',DATE(dt_diligence_started_legal)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_diligence_ended_legaut)),DATE_TRUNC('week',DATE(dt_diligence_started_legal))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    COUNT(DISTINCT id_offer) AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_diligence_ended_legaut) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
lrs2lre AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_diligence_started_legal)),DATE_TRUNC('week',DATE(dt_diligence_ended_legal))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_diligence_started_legal)),DATE_TRUNC('week',DATE(dt_diligence_ended_legal)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_diligence_started_legal)),DATE_TRUNC('week',DATE(dt_diligence_ended_legal))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    COUNT(DISTINCT id_offer) AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_started_legal) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
lre2de AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_diligence_ended_legal)),DATE_TRUNC('week',DATE(dt_diligence_ended))) < 20
                THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_diligence_ended_legal)),DATE_TRUNC('week',DATE(dt_diligence_ended)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_diligence_ended_legal)),DATE_TRUNC('week',DATE(dt_diligence_ended))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    COUNT(DISTINCT id_offer) AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_ended_legal) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
ccv2credstart AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_credit_started))) < 20
                THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_credit_started)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_credit_started))) >= 20
                THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    COUNT(DISTINCT id_offer) AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
credstart2credsent AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_credit_started)),DATE_TRUNC('week',DATE(dt_credit_approved))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_credit_started)),DATE_TRUNC('week',DATE(dt_credit_approved)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_credit_started)),DATE_TRUNC('week',DATE(dt_credit_approved))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    COUNT(DISTINCT id_offer) AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_credit_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
ccv2crnended AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_notes_registry_ended))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_notes_registry_ended)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_notes_registry_ended))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    COUNT(DISTINCT id_offer) AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
credsent2finstart AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_credit_approved)),DATE_TRUNC('week',DATE(dt_finan_started))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_credit_approved)),DATE_TRUNC('week',DATE(dt_finan_started)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_credit_approved)),DATE_TRUNC('week',DATE(dt_finan_started))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    COUNT(DISTINCT id_offer) AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_credit_approved) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
ccv2finstart AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_finan_started))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_finan_started)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_finan_started))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    COUNT(DISTINCT id_offer) AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
finstart2finended AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_finan_started)),DATE_TRUNC('week',DATE(dt_finan_ended))) < 20
        THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_finan_started)),DATE_TRUNC('week',DATE(dt_finan_ended)))
    WHEN datediff('week',DATE_TRUNC('week',DATE(dt_finan_started)),DATE_TRUNC('week',DATE(dt_finan_ended))) >= 20
        THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    COUNT(DISTINCT id_offer) finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_finan_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
ccv2mi AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_inicio))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_inicio)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_inicio))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    COUNT(DISTINCT id_offer) AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
),
mi2ma AS (
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
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_matricula_inicio)),DATE_TRUNC('week',DATE(dt_matricula_atualizada))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_matricula_inicio)),DATE_TRUNC('week',DATE(dt_matricula_atualizada)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_matricula_inicio)),DATE_TRUNC('week',DATE(dt_matricula_atualizada))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    COUNT(DISTINCT id_offer) AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_matricula_inicio) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
    CASE
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_atualizada))) < 20
            THEN 'W'||datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_atualizada)))
        WHEN datediff('week',DATE_TRUNC('week',DATE(dt_ccv_signed)),DATE_TRUNC('week',DATE(dt_matricula_atualizada))) >= 20
            THEN 'W20+'
    END AS weeks_conversion,
    NULL::BIGINT AS p2fc,
    NULL::BIGINT AS fc2q,
    NULL::BIGINT AS p2q,
    NULL::BIGINT AS q2o,
    NULL::BIGINT AS o2fl,
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    COUNT(DISTINCT id_offer) AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    NULL AS sales_company,
    NULL AS lead_processing_operation,
    is_3p_supply,
    supply_3p_partner,
    is_3p_demand,
    demand_3p_partner,
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
    hub_visit AS hub_visit,
    hub_offer AS hub_offer,
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
    NULL::BIGINT AS fl2ccv,
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS os2ccv,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS ccv2crnended,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS ccv2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    COUNT(DISTINCT id_offer) AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20
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
    SELECT * FROM fl2ccv
    UNION ALL
    SELECT * FROM vb2vc
    UNION ALL
    SELECT * FROM vb2os
    UNION ALL
    SELECT * FROM vb2oa
    UNION ALL
    SELECT * FROM vb2ccv
    UNION ALL
    SELECT * FROM vc2ccv
    UNION ALL
    SELECT * FROM vc2os
    UNION ALL
    SELECT * FROM vc2oa
    UNION ALL
    SELECT * FROM os2oa
    UNION ALL
    SELECT * FROM os2dq
    UNION ALL
    SELECT * FROM dq2oa
    UNION ALL
    SELECT * FROM os2ccv
    UNION ALL
    SELECT * FROM oa2ccv
    UNION ALL
    SELECT * FROM ccv2lts
    UNION ALL
    SELECT * FROM lts2lte
    UNION ALL
    SELECT * FROM lte2lrs
    UNION ALL
    SELECT * FROM lrs2lre
    UNION ALL
    SELECT * FROM lre2de
    UNION ALL
    SELECT * FROM ccv2credstart
    UNION ALL
    SELECT * FROM credstart2credsent
    UNION ALL
    SELECT * FROM ccv2crnended
    UNION ALL
    SELECT * FROM credsent2finstart
    UNION ALL
    SELECT * FROM ccv2finstart
    UNION ALL
    SELECT * FROM finstart2finended
    UNION ALL
    SELECT * FROM ccv2mi
    UNION ALL
    SELECT * FROM mi2ma
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
    ua.is_3p_supply,
    ua.supply_3p_partner,
    ua.is_3p_demand,
    ua.demand_3p_partner,
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
    ua.weeks_conversion,
    ua.p2fc,
    ua.fc2q,
    ua.p2q,
    ua.q2o,
    ua.o2fl,
    ua.fl2ccv,
    ua.vb2vc,
    ua.vb2os,
    ua.vb2oa,
    ua.vb2ccv,
    ua.vc2ccv,
    ua.vc2os,
    ua.vc2oa,
    ua.os2oa,
    ua.os2dq,
    ua.dq2oa,
    ua.os2ccv,
    ua.oa2ccv,
    ua.ccv2lts,
    ua.lts2lte,
    ua.lte2lrs,
    ua.lrs2lre,
    ua.lre2de,
    ua.ccv2credstart,
    ua.credstart2credsent,
    ua.ccv2crnended,
    ua.credsent2finstart,
    ua.ccv2finstart,
    ua.finstart2finended,
    ua.ccv2mi,
    ua.mi2ma,
    ua.ccv2ma,
    ua.ccv2pc
FROM
    union_all ua
RIGHT JOIN
    dim_date dd
        ON ua.base_date = dd.sk_date
WHERE
    dd.date BETWEEN '2020-01-01'
    AND current_date
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
    weeks_conversion,
    supply_3p_partner,
    demand_3p_partner,
    is_3p_supply,
    is_3p_demand,
    SUM(p2fc) AS p2fc,
    SUM(fc2q) AS fc2q,
    SUM(p2q) AS p2q,
    SUM(q2o) AS q2o,
    SUM(o2fl) AS o2fl,
    SUM(fl2ccv) AS fl2ccv,
    SUM(vb2vc) AS vb2vc,
    SUM(vb2os) AS vb2os,
    SUM(vb2oa) AS vb2oa,
    SUM(vb2ccv) AS vb2ccv,
    SUM(vc2ccv) AS vc2ccv,
    SUM(vc2os) AS vc2os,
    SUM(vc2oa) AS vc2oa,
    SUM(os2oa) AS os2oa,
    SUM(os2dq) AS os2dq,
    SUM(dq2oa) AS dq2oa,
    SUM(os2ccv) AS os2ccv,
    SUM(oa2ccv) AS oa2ccv,
    SUM(ccv2lts) AS ccv2lts,
    SUM(lts2lte) AS lts2lte,
    SUM(lte2lrs) AS lte2lrs,
    SUM(lrs2lre) AS lrs2lre,
    SUM(lre2de) AS lre2de,
    SUM(ccv2credstart) AS ccv2credstart,
    SUM(credstart2credsent) AS credstart2credsent,
    SUM(ccv2crnended) AS ccv2crnended,
    SUM(credsent2finstart) AS credsent2finstart,
    SUM(ccv2finstart) AS ccv2finstart,
    SUM(finstart2finended) AS finstart2finended,
    SUM(ccv2mi) AS ccv2mi,
    SUM(mi2ma) AS mi2ma,
    SUM(ccv2ma) AS ccv2ma,
    SUM(ccv2pc) AS ccv2pc,
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
        weeks_conversion,
        hub_visit,
        hub_offer,
        is_3p_supply,
        supply_3p_partner,
        is_3p_demand,
        demand_3p_partner