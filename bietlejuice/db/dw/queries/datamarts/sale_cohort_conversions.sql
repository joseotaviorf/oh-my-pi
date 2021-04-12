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
	    WHEN lf.mkt_origin IN ('Other', 'Backend') THEN 'Non Paid'
        WHEN lf.mkt_channel IN ('CRM/Notification', 'LeadEnrichment', 'Organic') AND lf.mkt_origin = 'Owner PWA' THEN 'Non Paid'
        WHEN lf.mkt_channel = 'Paid' AND lf.mkt_origin = 'Owner PWA' THEN 'Paid'
	END AS mkt_type,
	CASE
	    WHEN dr.city_group NOT IN ('RMSP', 'Rio de Janeiro') THEN 'Out of coverage area'
	    WHEN dr.city_group IN ('RMSP', 'Rio de Janeiro') THEN dr.city_group
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
    datalake_firestore_prod.monday mo
),
sale_bookings AS (
SELECT
	fv.sk_house AS id_property,
	fv.sk_buyer AS id_visitor,
	fv.sk_booking,
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
        DATE_TRUNC('week', DATE(sk_offer_submitted_date)) AS week_start,
        DATE(sk_offer_submitted_date) AS date,
        sk_house,
        sk_offer,
        sk_buyer
    FROM
    	sale.fact_offers
    WHERE
    	sk_offer_submitted_date > 0
    ),
    fact_oa AS (
    SELECT
        DATE_TRUNC('week', DATE(sk_offer_accepted_date)) AS week_start,
        DATE(sk_offer_accepted_date) AS date,
        sk_house,
        sk_offer,
        sk_buyer
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
    COALESCE(fact_os.sk_house,fact_oa.sk_house) AS sk_house,
    COALESCE(fact_os.sk_buyer,fact_oa.sk_buyer) AS sk_buyer,
    MAX(fact_os.date) AS os_date,
    MAX(fact_oa.date) AS oa_date,
    MAX(fact_ccv.date) AS ccv_date
FROM
    fact_os
FULL OUTER JOIN
    fact_oa
        ON fact_os.sk_offer = fact_oa.sk_offer
--        AND fact_os.date = fact_oa.date
FULL OUTER JOIN
    fact_ccv
        ON fact_os.sk_offer = fact_ccv.sk_offer
--        AND fact_os.date = fact_ccv.date
GROUP BY 1, 2, 3
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
	COALESCE(offers.id_offer,sc.sk_offer) AS id_offer,
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
	offers.dt_matricula_inicio,
	offers.dt_matricula_atualizada,
	offers.dt_entrega_chaves,
	offers.dt_finan_started,
	offers.dt_finan_ended,
	sc.os_date,
	sc.oa_date,
	sc.ccv_date
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
	sde.dt_matricula_inicio,
	sde.dt_matricula_atualizada,
	sde.dt_entrega_chaves,
	sde.dt_finan_started,
	sde.dt_finan_ended,
	sde.id_offer,
	db.sk_booking,
	db.dt_created,
	db.dt_completed,
	db.city_group
FROM
    sale_demand_events sde
FULL OUTER JOIN
    sale_bookings db
        ON (sde.id_house = db.id_property AND sde.id_buyer = db.id_visitor)
),
sale_demand_classification AS (
SELECT
    sdc.id_offer,
    sdc.sk_booking,
	sdc.id_buyer,
	sdc.id_house,
	CASE
	    WHEN COALESCE(sdr.city_group,sdc.city_group) NOT IN ('RMSP', 'Rio de Janeiro') THEN 'Out of coverage area'
	    WHEN COALESCE(sdr.city_group,sdc.city_group) IN ('RMSP', 'Rio de Janeiro') THEN COALESCE(sdr.city_group,sdc.city_group)
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
	sdc.dt_matricula_inicio,
	sdc.dt_matricula_atualizada,
	sdc.dt_entrega_chaves,
	sdc.dt_finan_started,
	sdc.dt_finan_ended,
	fsf.first_event AS first_touchpoint,
	fsf.higher_intent_before_offer,
	fsf.higher_intent_after_offer
FROM
    sale_demand_events_complete sdc
LEFT JOIN
    sale.fact_sale_flows fsf
        ON sdc.id_buyer = fsf.sk_buyer::VARCHAR
        AND sdc.id_house = fsf.sk_house::VARCHAR
LEFT JOIN
    sale_demand_region sdr
        ON sdr.id_house::VARCHAR = sdc.id_house
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
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    NULL AS first_origin_demand,
    NULL AS origin_before_offer,
    NULL AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_first_contact_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
   NULL AS first_origin_demand,
   NULL AS origin_before_offer,
   NULL AS origin_after_offer,
   NULL AS form_of_payment,
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
   NULL::BIGINT AS vb2vc,
   NULL::BIGINT AS vb2os,
   NULL::BIGINT AS vb2oa,
   NULL::BIGINT AS vb2ccv,
   NULL::BIGINT AS vc2os,
   NULL::BIGINT AS vc2oa,
   NULL::BIGINT AS os2oa,
   NULL::BIGINT AS os2dq,
   NULL::BIGINT AS dq2oa,
   NULL::BIGINT AS oa2ccv,
   NULL::BIGINT AS ccv2lts,
   NULL::BIGINT AS lts2lte,
   NULL::BIGINT AS lte2lrs,
   NULL::BIGINT AS lrs2lre,
   NULL::BIGINT AS lre2de,
   NULL::BIGINT AS ccv2credstart,
   NULL::BIGINT AS credstart2credsent,
   NULL::BIGINT AS credsent2finstart,
   NULL::BIGINT AS finstart2finended,
   NULL::BIGINT AS ccv2mi,
   NULL::BIGINT AS mi2ma,
   NULL::BIGINT AS ccv2ma,
   NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_prospect_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
   NULL AS first_origin_demand,
   NULL AS origin_before_offer,
   NULL AS origin_after_offer,
   NULL AS form_of_payment,
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
   NULL::BIGINT AS vb2vc,
   NULL::BIGINT AS vb2os,
   NULL::BIGINT AS vb2oa,
   NULL::BIGINT AS vb2ccv,
   NULL::BIGINT AS vc2os,
   NULL::BIGINT AS vc2oa,
   NULL::BIGINT AS os2oa,
   NULL::BIGINT AS os2dq,
   NULL::BIGINT AS dq2oa,
   NULL::BIGINT AS oa2ccv,
   NULL::BIGINT AS ccv2lts,
   NULL::BIGINT AS lts2lte,
   NULL::BIGINT AS lte2lrs,
   NULL::BIGINT AS lrs2lre,
   NULL::BIGINT AS lre2de,
   NULL::BIGINT AS ccv2credstart,
   NULL::BIGINT AS credstart2credsent,
   NULL::BIGINT AS credsent2finstart,
   NULL::BIGINT AS finstart2finended,
   NULL::BIGINT AS ccv2mi,
   NULL::BIGINT AS mi2ma,
   NULL::BIGINT AS ccv2ma,
   NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_qualified_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
   NULL AS first_origin_demand,
   NULL AS origin_before_offer,
   NULL AS origin_after_offer,
   NULL AS form_of_payment,
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
   COUNT(slf.sk_opportunity_date) AS o2fl,
   NULL::BIGINT AS vb2vc,
   NULL::BIGINT AS vb2os,
   NULL::BIGINT AS vb2oa,
   NULL::BIGINT AS vb2ccv,
   NULL::BIGINT AS vc2os,
   NULL::BIGINT AS vc2oa,
   NULL::BIGINT AS os2oa,
   NULL::BIGINT AS os2dq,
   NULL::BIGINT AS dq2oa,
   NULL::BIGINT AS oa2ccv,
   NULL::BIGINT AS ccv2lts,
   NULL::BIGINT AS lts2lte,
   NULL::BIGINT AS lte2lrs,
   NULL::BIGINT AS lrs2lre,
   NULL::BIGINT AS lre2de,
   NULL::BIGINT AS ccv2credstart,
   NULL::BIGINT AS credstart2credsent,
   NULL::BIGINT AS credsent2finstart,
   NULL::BIGINT AS finstart2finended,
   NULL::BIGINT AS ccv2mi,
   NULL::BIGINT AS mi2ma,
   NULL::BIGINT AS ccv2ma,
   NULL::BIGINT AS ccv2pc
FROM
    sale_listing_flows_adjust AS slf
WHERE
    slf.sk_opportunity_date > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
   first_touchpoint AS first_origin_demand,
   higher_intent_before_offer AS origin_before_offer,
   higher_intent_after_offer AS origin_after_offer,
   NULL AS form_of_payment,
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
   COUNT(DISTINCT sk_booking) AS vb2vc,
   NULL::BIGINT AS vb2os,
   NULL::BIGINT AS vb2oa,
   NULL::BIGINT AS vb2ccv,
   NULL::BIGINT AS vc2os,
   NULL::BIGINT AS vc2oa,
   NULL::BIGINT AS os2oa,
   NULL::BIGINT AS os2dq,
   NULL::BIGINT AS dq2oa,
   NULL::BIGINT AS oa2ccv,
   NULL::BIGINT AS ccv2lts,
   NULL::BIGINT AS lts2lte,
   NULL::BIGINT AS lte2lrs,
   NULL::BIGINT AS lrs2lre,
   NULL::BIGINT AS lre2de,
   NULL::BIGINT AS ccv2credstart,
   NULL::BIGINT AS credstart2credsent,
   NULL::BIGINT AS credsent2finstart,
   NULL::BIGINT AS finstart2finended,
   NULL::BIGINT AS ccv2mi,
   NULL::BIGINT AS mi2ma,
   NULL::BIGINT AS ccv2ma,
   NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    COUNT(DISTINCT sk_booking) AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    COUNT(DISTINCT sk_booking) AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    COUNT(DISTINCT sk_booking) AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_created) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
   first_touchpoint AS first_origin_demand,
   higher_intent_before_offer AS origin_before_offer,
   higher_intent_after_offer AS origin_after_offer,
   NULL AS form_of_payment,
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
   NULL::BIGINT AS vb2vc,
   NULL::BIGINT AS vb2os,
   NULL::BIGINT AS vb2oa,
   NULL::BIGINT AS vb2ccv,
   COUNT(DISTINCT sk_booking) AS vc2os,
   NULL::BIGINT AS vc2oa,
   NULL::BIGINT AS os2oa,
   NULL::BIGINT AS os2dq,
   NULL::BIGINT AS dq2oa,
   NULL::BIGINT AS oa2ccv,
   NULL::BIGINT AS ccv2lts,
   NULL::BIGINT AS lts2lte,
   NULL::BIGINT AS lte2lrs,
   NULL::BIGINT AS lrs2lre,
   NULL::BIGINT AS lre2de,
   NULL::BIGINT AS ccv2credstart,
   NULL::BIGINT AS credstart2credsent,
   NULL::BIGINT AS credsent2finstart,
   NULL::BIGINT AS finstart2finended,
   NULL::BIGINT AS ccv2mi,
   NULL::BIGINT AS mi2ma,
   NULL::BIGINT AS ccv2ma,
   NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_completed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
   first_touchpoint AS first_origin_demand,
   higher_intent_before_offer AS origin_before_offer,
   higher_intent_after_offer AS origin_after_offer,
   NULL AS form_of_payment,
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
   NULL::BIGINT AS vb2vc,
   NULL::BIGINT AS vb2os,
   NULL::BIGINT AS vb2oa,
   NULL::BIGINT AS vb2ccv,
   NULL::BIGINT AS vc2os,
   COUNT(DISTINCT sk_booking) AS vc2oa,
   NULL::BIGINT AS os2oa,
   NULL::BIGINT AS os2dq,
   NULL::BIGINT AS dq2oa,
   NULL::BIGINT AS oa2ccv,
   NULL::BIGINT AS ccv2lts,
   NULL::BIGINT AS lts2lte,
   NULL::BIGINT AS lte2lrs,
   NULL::BIGINT AS lrs2lre,
   NULL::BIGINT AS lre2de,
   NULL::BIGINT AS ccv2credstart,
   NULL::BIGINT AS credstart2credsent,
   NULL::BIGINT AS credsent2finstart,
   NULL::BIGINT AS finstart2finended,
   NULL::BIGINT AS ccv2mi,
   NULL::BIGINT AS mi2ma,
   NULL::BIGINT AS ccv2ma,
   NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_completed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    COUNT(DISTINCT id_offer) AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    COUNT(DISTINCT id_offer) AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_offer_sent) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT  AS os2dq,
    COUNT(DISTINCT id_offer)AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_deal_qualified) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    COUNT(DISTINCT id_offer) AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_offer_accepted) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    COUNT(DISTINCT id_offer) AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    COUNT(DISTINCT id_offer) AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_started_legaut) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    COUNT(DISTINCT sk_booking) AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    date(dt_diligence_ended_legaut) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    COUNT(DISTINCT sk_booking) AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_started_legal) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    COUNT(DISTINCT sk_booking) AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_diligence_ended_legal) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
	first_touchpoint AS first_origin_demand,
	higher_intent_before_offer AS origin_before_offer,
	higher_intent_after_offer AS origin_after_offer,
	NULL AS form_of_payment,
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
	NULL::BIGINT AS vb2vc,
	NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
	NULL::BIGINT AS os2oa,
	NULL::BIGINT AS os2dq,
	NULL::BIGINT AS dq2oa,
	NULL::BIGINT AS oa2ccv,
	NULL::BIGINT AS ccv2lts,
	NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
	NULL::BIGINT AS lrs2lre,
	NULL::BIGINT AS lre2de,
	COUNT(DISTINCT sk_booking) AS ccv2credstart,
	NULL::BIGINT AS credstart2credsent,
	NULL::BIGINT AS credsent2finstart,
	NULL::BIGINT AS finstart2finended,
	NULL::BIGINT AS ccv2mi,
        NULL::BIGINT AS mi2ma,
	NULL::BIGINT AS ccv2ma,
	NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    COUNT(DISTINCT sk_booking) AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_credit_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    COUNT(DISTINCT sk_booking) AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_credit_approved) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    NULL AS form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    COUNT(DISTINCT sk_booking) finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_finan_started) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    COUNT(DISTINCT id_offer) AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    COUNT(DISTINCT id_offer) AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_matricula_inicio) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    first_touchpoint AS first_origin_demand,
    higher_intent_before_offer AS origin_before_offer,
    higher_intent_after_offer AS origin_after_offer,
    form_of_payment,
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
    NULL::BIGINT AS vb2vc,
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    COUNT(DISTINCT id_offer) AS ccv2ma,
    NULL::BIGINT AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
    NULL::BIGINT AS vb2os,
    NULL::BIGINT AS vb2oa,
    NULL::BIGINT AS vb2ccv,
    NULL::BIGINT AS vc2os,
    NULL::BIGINT AS vc2oa,
    NULL::BIGINT AS os2oa,
    NULL::BIGINT AS os2dq,
    NULL::BIGINT AS dq2oa,
    NULL::BIGINT AS oa2ccv,
    NULL::BIGINT AS ccv2lts,
    NULL::BIGINT AS lts2lte,
    NULL::BIGINT AS lte2lrs,
    NULL::BIGINT AS lrs2lre,
    NULL::BIGINT AS lre2de,
    NULL::BIGINT AS ccv2credstart,
    NULL::BIGINT AS credstart2credsent,
    NULL::BIGINT AS credsent2finstart,
    NULL::BIGINT AS finstart2finended,
    NULL::BIGINT AS ccv2mi,
    NULL::BIGINT AS mi2ma,
    NULL::BIGINT AS ccv2ma,
    COUNT(DISTINCT id_offer) AS ccv2pc
FROM
    sale_demand_classification
WHERE
    DATE(dt_ccv_signed) > 0
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14
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
	SELECT * FROM vb2os
	UNION ALL
	SELECT * FROM vb2oa
	UNION ALL
	SELECT * FROM vb2ccv
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
	SELECT * FROM credsent2finstart
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
	ua.weeks_conversion,
	ua.p2fc,
	ua.fc2q,
	ua.p2q,
	ua.q2o,
	ua.o2fl,
	ua.vb2vc,
	ua.vb2os,
	ua.vb2oa,
	ua.vb2ccv,
	ua.vc2os,
	ua.vc2oa,
	ua.os2oa,
	ua.os2dq,
	ua.dq2oa,
	ua.oa2ccv,
	ua.ccv2lts,
	ua.lts2lte,
    ua.lte2lrs,
	ua.lrs2lre,
	ua.lre2de,
	ua.ccv2credstart,
	ua.credstart2credsent,
	ua.credsent2finstart,
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
	weeks_conversion,
	SUM(p2fc) AS p2fc,
	SUM(fc2q) AS fc2q,
	SUM(p2q) AS p2q,
   	SUM(q2o) AS q2o,
	SUM(o2fl) AS o2fl,
	SUM(vb2vc) AS vb2vc,
	SUM(vb2os) AS vb2os,
	SUM(vb2oa) AS vb2oa,
	SUM(vb2ccv) AS vb2ccv,
	SUM(vc2os) AS vc2os,
	SUM(vc2oa) AS vc2oa,
	SUM(os2oa) AS os2oa,
	SUM(os2dq) AS os2dq,
	SUM(dq2oa) AS dq2oa,
	SUM(oa2ccv) AS oa2ccv,
	SUM(ccv2lts) AS ccv2lts,
	SUM(lts2lte) AS lts2lte,
    SUM(lte2lrs) AS lte2lrs,
	SUM(lrs2lre) AS lrs2lre,
	SUM(lre2de) AS lre2de,
	SUM(ccv2credstart) AS ccv2credstart,
	SUM(credstart2credsent) AS credstart2credsent,
	SUM(credsent2finstart) AS credsent2finstart,
	SUM(finstart2finended) AS finstart2finended,
	SUM(ccv2mi) AS ccv2mi,
	SUM(mi2ma) AS mi2ma,
	SUM(ccv2ma) AS ccv2ma,
	SUM(ccv2pc) AS ccv2pc,
	current_timestamp AS ts_load
FROM
    union_all_date
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
	 sales_company,
	 lead_processing_operation,
	 first_origin_demand,
	 origin_before_offer,
	 origin_after_offer,
	 form_of_payment,
	 weeks_conversion
ORDER BY 2 DESC
