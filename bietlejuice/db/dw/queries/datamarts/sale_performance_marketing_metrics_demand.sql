WITH
buyer_prospect_status as (
    SELECT
        sk_buyer,
        city_group,
        ts_start,
        ts_end,
        status,
        status_detail,
        LAG(status) OVER(PARTITION BY sk_buyer, city_group order by ts_start) as last_status,
        LEAD(status) OVER(PARTITION BY sk_buyer, city_group order by ts_start) as next_status
    FROM
        datamarts.buyer_prospect_status
    WHERE
        ts_start >= ts_first_activation
),
dim_house AS (
    SELECT
        id AS sk_house,
        id_region AS sk_region
    FROM
        datalake_ebdb_clean_prod.house
    GROUP BY 1,2
),
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
events AS (
    SELECT
        fsf.sk_sale_flow,
        fsf.sk_buyer,
        fsf.sk_house,
        fsf.sk_region,
        db.mkt_origin,
        db.mkt_channel,
        db.mkt_medium,
        db.mkt_source,
        db.utm_medium,
        db.utm_source,
        db.utm_campaign,
        db.utm_term,
        db.utm_content,
        db.dt_created AS ts_event,
        'Booking' AS flow_event
    FROM
        dim_booking AS db
        JOIN sale.fact_visits AS fv
            USING(sk_booking)
        JOIN sale.fact_sale_flows AS fsf
            ON fsf.sk_sale_flow = fv.sk_sale_flow
    WHERE
        db.sk_booking > 0
        AND db.visit_intent = 'SALE'
        AND db.type = 'Visita'
        AND db.dt_created IS NOT NULL

    UNION ALL

    SELECT
        fsf.sk_sale_flow,
        fsf.sk_buyer,
        fsf.sk_house,
        fsf.sk_region,
        o.mkt_origin,
        o.mkt_channel,
        o.mkt_medium,
        o.mkt_source,
        o.utm_medium,
        o.utm_source,
        o.utm_campaign,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        o.ts_offer_submitted AS ts_event,
        'Offer' AS flow_event
    FROM
        sale.dim_offer AS o
        JOIN sale.fact_offers AS fo
            USING(sk_offer)
        JOIN sale.fact_sale_flows AS fsf
            ON fsf.sk_sale_flow = fo.sk_sale_flow
    --
    UNION ALL
    --
    SELECT
        tenant_id || '_' || house_id AS sk_sale_flow,
        tenant_id::INT AS sk_buyer,
        house_id::INT AS id_house,
        dh.sk_region,
        a.mkt_origin,
        a.mkt_channel,
        a.mkt_medium,
        a.mkt_source,
        a.utm_medium,
        a.utm_source,
        a.utm_campaign,
        a.utm_term,
        a.utm_content,
        a.first_message_ts::timestamp AS ts_event,
        'Talk to Agent' AS flow_event
    FROM
        datamarts.talk_to_agent AS a
        JOIN dim_house AS dh
            ON a.house_id = dh.sk_house
        JOIN sale.fact_sale_flows AS fsf
            ON fsf.sk_sale_flow = a.tenant_id || '_' || a.house_id
    WHERE
        a.business_context = 'SALE'
        AND a.first_message_ts IS NOT NULL
),
---------------------------------------------------------
-- Order events by user and sale_flows (user || house) --
---------------------------------------------------------
sale_flows AS (
    SELECT
        DATE(evt.ts_event) AS dt_event,
        evt.ts_event,
        dr.city_group,
        evt.flow_event,
        evt.mkt_origin,
        evt.mkt_channel,
        evt.mkt_medium,
        evt.mkt_source,
        evt.utm_medium,
        evt.utm_source,
        evt.utm_campaign AS campaign_name,
        evt.utm_campaign,
        evt.utm_term,
        evt.utm_content,
        evt.sk_sale_flow,
        evt.sk_buyer,
        evt.sk_house,
        ROW_NUMBER() OVER(PARTITION BY evt.sk_sale_flow
                            ORDER BY evt.ts_event) AS sale_flow_order,
        ROW_NUMBER() OVER(PARTITION BY evt.sk_buyer
                            ORDER BY evt.ts_event) AS buyer_prospect_order
    FROM
        events AS evt
        JOIN dim_region AS dr
            USING(sk_region)
        LEFT JOIN sale.fact_offers AS fo
            ON evt.sk_sale_flow = fo.sk_sale_flow
),
sale_funnel AS (
    SELECT
        fsf.sk_sale_flow,
        fo.sk_offer,
        fv.sk_booking,
        dd_os.date AS dt_offer_submitted,
        dd_oa.date AS dt_offer_accepted,
        dd_ccv.date AS dt_sale_agreement_signed,
        dd_vb.date AS dt_booking_created,
        dd_vc.date AS dt_visit_completed
    FROM
        sale.fact_sale_flows AS fsf
        LEFT JOIN sale.fact_offers AS fo
            ON fsf.sk_sale_flow = fo.sk_sale_flow
        LEFT JOIN sale.fact_visits AS fv
            ON fsf.sk_sale_flow = fv.sk_sale_flow
        LEFT JOIN dim_date AS dd_os
            ON fo.sk_offer_submitted_date = dd_os.sk_date
        LEFT JOIN dim_date AS dd_oa
            ON fo.sk_offer_accepted_date = dd_oa.sk_date
        LEFT JOIN dim_date AS dd_ccv
            ON fo.sk_sale_agreement_signed_date = dd_ccv.sk_date
        LEFT JOIN dim_date AS dd_vb
            ON fv.sk_booking_created_date = dd_vb.sk_date
        LEFT JOIN dim_date AS dd_vc
            ON fv.sk_visit_completed_date = dd_vc.sk_date
),
sale_flows_funnel_events AS (
    SELECT
        sf.dt_event,
        sf.ts_event,
        bps.status,
        bps.status_detail,
        bps.next_status,
        bps.ts_start AS ts_status_start,
        bps.ts_end AS ts_status_end,
        sf.city_group,
        sf.flow_event,
        sf.mkt_origin,
        sf.mkt_channel,
        sf.mkt_medium,
        sf.mkt_source,
        sf.utm_medium,
        sf.utm_source,
        sf.utm_campaign AS campaign_name,
        sf.utm_campaign,
        CASE
            WHEN LOWER(sf.utm_campaign) LIKE '%sale%'
                    OR LOWER(sf.utm_campaign) LIKE '%girafa%'
                    OR LOWER(sf.utm_campaign) LIKE '%vender%'
                    OR LOWER(sf.utm_campaign) = 'whatsapp_s'
                THEN 'Sale'
            WHEN sf.utm_campaign IS NULL
                    OR sf.utm_campaign = ''
                    OR LOWER(sf.utm_campaign) LIKE '%branded%'
                THEN 'Organic'
            ELSE 'Rental'
        END AS campaign_context,
        sf.utm_term,
        sf.utm_content,
        sf.sk_sale_flow,
        sf.sk_buyer,
        sf.sk_house,
        funnel.sk_offer,
        funnel.sk_booking,
        funnel.dt_offer_submitted,
        funnel.dt_offer_accepted,
        funnel.dt_sale_agreement_signed,
        funnel.dt_booking_created,
        funnel.dt_visit_completed,
        sf.sale_flow_order,
        sf.buyer_prospect_order,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS recovered_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        NULL::FLOAT AS marketing_cost
    FROM
        sale_flows AS sf
        LEFT JOIN sale_funnel AS funnel
            ON sf.sk_sale_flow = funnel.sk_sale_flow
        LEFT JOIN buyer_prospect_status AS bps
            ON sf.ts_event >= bps.ts_start
            AND sf.ts_event <= COALESCE(bps.ts_end, CURRENT_DATE)
            AND sf.sk_buyer = bps.sk_buyer
            AND sf.city_group = bps.city_group
            AND bps.status = 'ACTIVE'
    WHERE
        sale_flow_order = 1
),
--------------------------------------------------------------------------------------
-- Query Performance Marketing ForSale Demand targets and introduce NULLs for UNION --
--------------------------------------------------------------------------------------
targets AS (
    SELECT
        bd.date::DATE,
        bd.date::TIMESTAMP AS ts_event,
        NULL::TEXT AS status,
        NULL:: TEXT AS status_detail,
        NULL:: TEXT AS next_status,
        NULL::TIMESTAMP AS ts_status_start,
        NULL::TIMESTAMP AS ts_status_end,
        bd.city AS city_group,
        NULL::TEXT AS flow_event,
        'Tenants PWA' AS mkt_origin,
        bd.mkt_channel,
        bd.mkt_medium,
        bd.mkt_source,
        NULL::TEXT AS utm_medium,
        NULL::TEXT AS utm_source,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS utm_campaign,
        'Sale' AS campaign_context,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS sk_sale_flow,
        NULL::INT AS sk_buyer,
        NULL::INT AS sk_house,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_accepted,
        NULL::DATE AS dt_sale_agreement_signed,
        NULL::DATE AS dt_booking_created,
        NULL::DATE AS dt_visit_completed,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        REPLACE(bd.daily_value, ',', '')::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS recovered_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        NULL::FLOAT AS marketing_cost
    FROM
        datalake_gsheets_clean_prod.mkt_cost_per_source AS bd
    WHERE
        LOWER(business) = 'sale'
    UNION ALL
    SELECT
        bp.dt_target::DATE,
        bp.dt_target::TIMESTAMP AS ts_event,
        NULL::TEXT AS status,
        NULL:: TEXT AS status_detail,
        NULL:: TEXT AS next_status,
        NULL::TIMESTAMP AS ts_status_start,
        NULL::TIMESTAMP AS ts_status_end,
        bp.city_group,
        NULL::TEXT AS flow_event,
        'Tenants PWA' AS mkt_origin,
        bp.mkt_channel,
        bp.mkt_medium,
        bp.mkt_source,
        NULL::TEXT AS utm_medium,
        NULL::TEXT AS utm_source,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS utm_campaign,
        bp.context AS campaign_context,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS sk_sale_flow,
        NULL::INT AS sk_buyer,
        NULL::INT AS sk_house,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_accepted,
        NULL::DATE AS dt_sale_agreement_signed,
        NULL::DATE AS dt_booking_created,
        NULL::DATE AS dt_visit_completed,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        NULL::FLOAT AS budget,
        bp.nbp_target::FLOAT AS new_buyer_prospects_target,
        bp.rbp_target::FLOAT AS recovered_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        NULL::FLOAT AS marketing_cost
    FROM
        datalake_gsheets_clean_prod.sale_nbp_source_targets AS bp
    UNION ALL
    SELECT
        date::DATE,
        date::TIMESTAMP AS ts_event,
        NULL::TEXT AS status,
        NULL:: TEXT AS status_detail,
        NULL:: TEXT AS next_status,
        NULL::TIMESTAMP AS ts_status_start,
        NULL::TIMESTAMP AS ts_status_end,
        city_group,
        NULL::TEXT AS flow_event,
        'Tenants PWA' AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        NULL::TEXT AS utm_medium,
        NULL::TEXT AS utm_source,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS utm_campaign,
        'Sale' AS campaign_context,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS sk_sale_flow,
        NULL::INT AS sk_buyer,
        NULL::INT AS sk_house,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_accepted,
        NULL::DATE AS dt_sale_agreement_signed,
        NULL::DATE AS dt_booking_created,
        NULL::DATE AS dt_visit_completed,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS recovered_buyer_prospects_target,
        sf_target::FLOAT AS sale_flows_target,
        NULL::FLOAT AS marketing_cost
    FROM
        datalake_gsheets_clean_prod.sale_flows_targets
),
----------------------------------------------------------------------------------------------------------------------------
-- Query Performance Marketing Investment ForSale Demand costs (mkt_origin = 'Tenants PWA') and introduce NULLs for UNION --
----------------------------------------------------------------------------------------------------------------------------
investment AS (
    SELECT
        dd.date,
        dd.date::TIMESTAMP AS ts_event,
        NULL::TEXT AS status,
        NULL:: TEXT AS status_detail,
        NULL:: TEXT AS next_status,
        NULL::TIMESTAMP AS ts_status_start,
        NULL::TIMESTAMP AS ts_status_end,
        city_group,
        NULL::TEXT AS flow_event,
        'Tenants PWA' AS mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        NULL::TEXT AS utm_medium,
        NULL::TEXT AS utm_source,
        campaign_name,
        utm_campaign,
        'Sale' AS campaign_context,
        utm_term,
        utm_content,
        NULL::TEXT AS sk_sale_flow,
        NULL::INT AS sk_buyer,
        NULL::INT AS sk_house,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_accepted,
        NULL::DATE AS dt_sale_agreement_signed,
        NULL::DATE AS dt_booking_created,
        NULL::DATE AS dt_visit_completed,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS recovered_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        SUM(co.cost::FLOAT) AS marketing_cost
    FROM
        datalake_marketing_costs_prod.daily_costs AS co
    JOIN dim_date AS dd
        ON dd.sk_date = co.id_date
    WHERE
        co.mkt_origin = 'Tenants PWA - Sale'
        AND dd.date >= DATE('2020-01-01')
        AND co.mkt_medium != 'Branding'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35
),
-------------------------------------------------------------------------------------
-- Query Performance Marketing Rental Demand targets and introduce NULLs for UNION --
-------------------------------------------------------------------------------------
deactivations AS (
    SELECT
        DATE(ts_start) AS dt_event,
        ts_start AS ts_event,
        status,
        status_detail,
        NULL:: TEXT AS next_status,
        ts_start AS ts_status_start,
        ts_end AS ts_status_end,
        city_group,
        NULL::TEXT AS flow_event,
        NULL::TEXT AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        NULL::TEXT AS utm_medium,
        NULL::TEXT AS utm_source,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS campaign_context,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS sk_sale_flow,
        sk_buyer,
        NULL::INT AS sk_house,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_accepted,
        NULL::DATE AS dt_sale_agreement_signed,
        NULL::DATE AS dt_booking_created,
        NULL::DATE AS dt_visit_completed,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS recovered_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        0.0 AS marketing_cost
    FROM
        buyer_prospect_status
    WHERE
        status IN ('CHURNED', 'SIGNED CCV')
        AND last_status = 'ACTIVE'
)
SELECT
    *
FROM
    sale_flows_funnel_events
UNION ALL
SELECT
    *
FROM
    targets
UNION ALL
SELECT
    *
FROM
    investment
UNION ALL
SELECT
    *
FROM
    deactivations;