WITH
dim_house AS (
    SELECT
        id AS sk_house,
        id_region AS sk_region
    FROM
        datalake_ebdb_clean_prod.house
    GROUP BY 1,2
),
taxonomy AS (
    SELECT DISTINCT
        td.Origin as mkt_origin,
        td.Channel as mkt_channel,
        td.Medium as mkt_medium
    FROM
        datalake_raw.gsheets_taxonomy_demand AS td
    WHERE
        td.Channel NOT IN  ('Paid Retention', 'Paid Traffic')
),
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
bookings AS (
    SELECT
        fsf.sk_sale_flow,
        fsf.sk_buyer,
        fsf.sk_house,
        fsf.sk_region,
        db.mkt_origin,
        db.mkt_channel,
        db.mkt_medium,
        db.mkt_source,
        db.utm_campaign,
        db.utm_term,
        db.utm_content,
        db.dt_created AS ts_event,
        sk_booking,
        NULL::TEXT AS sk_offer,
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
),
offers AS (
    SELECT
        fsf.sk_sale_flow,
        fsf.sk_buyer,
        fsf.sk_house,
        fsf.sk_region,
        o.mkt_origin,
        o.mkt_channel,
        o.mkt_medium,
        o.mkt_source,
        o.utm_campaign,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        o.ts_offer_submitted AS ts_event,
        NULL::INT AS sk_booking,
        sk_offer,
        'Offer' AS flow_event
    FROM
        sale.dim_offer AS o
        JOIN sale.fact_offers AS fo
            USING(sk_offer)
        JOIN sale.fact_sale_flows AS fsf
            ON fsf.sk_sale_flow = fo.sk_sale_flow
),
tta AS (
    SELECT
        tenant_id || '_' || house_id AS sk_sale_flow,
        tenant_id::INT AS sk_buyer,
        house_id::INT AS id_house,
        dh.sk_region,
        a.mkt_origin,
        a.mkt_channel,
        a.mkt_medium,
        a.mkt_source,
        a.utm_campaign,
        a.utm_term,
        a.utm_content,
        a.first_message_ts::timestamp AS ts_event,
        NULL::INT AS sk_booking,
        NULL::TEXT AS sk_offer,
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
events AS (
    SELECT
        *
    FROM
        bookings
    UNION ALL
    SELECT
        *
    FROM
        offers
    UNION ALL
    SELECT
        *
    FROM
        tta
),
---------------------------------------------------------
-- Order events by user and sale_flows (user || house) --
---------------------------------------------------------
sale_flows AS (
    SELECT
        DATE(evt.ts_event) AS dt_event,
        dr.city_group,
        evt.flow_event,
        evt.mkt_origin,
        evt.mkt_channel,
        evt.mkt_medium,
        evt.mkt_source,
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
),
sale_flows_funnel_events AS (
    SELECT
        sf.dt_event,
        sf.city_group,
        sf.flow_event,
        sf.mkt_origin,
        sf.mkt_channel,
        sf.mkt_medium,
        sf.mkt_source,
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
        b.ts_event::DATE AS dt_booking_created,
        b.sk_booking,
        o.ts_event::DATE AS dt_offer_submitted,
        o.sk_offer,
        sf.sale_flow_order,
        sf.buyer_prospect_order,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        NULL::FLOAT AS marketing_cost
    FROM
        sale_flows AS sf
        LEFT JOIN bookings AS b
            ON sf.sk_sale_flow = b.sk_sale_flow
        LEFT JOIN offers AS o
            ON sf.sk_sale_flow = o.sk_sale_flow
    WHERE
        sale_flow_order = 1
),
--------------------------------------------------------------------------------------
-- Query Performance Marketing ForSale Demand targets and introduce NULLs for UNION --
--------------------------------------------------------------------------------------
targets AS (
    SELECT
        bd.date::DATE,
        bd.city AS city_group,
        NULL::TEXT AS flow_event,
        'Tenants PWA' AS mkt_origin,
        CASE
            WHEN bd.mkt_medium = 'Not Mapped'
                THEN 'Not Mapped'
            ELSE t.mkt_channel
        END AS mkt_channel,
        bd.mkt_medium,
        bd.mkt_source,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS utm_campaign,
        'Sale' AS campaign_context,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS sk_sale_flow,
        NULL::INT AS sk_buyer,
        NULL::INT AS sk_house,
        NULL::DATE AS dt_booking_created,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        bd.daily__value::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        NULL::FLOAT AS marketing_cost
    FROM
        datalake_raw.gsheets_mkt_cost_per_source AS bd
        LEFT JOIN taxonomy AS t
            ON bd.mkt_medium = t.mkt_medium
    WHERE
        LOWER(business) = 'sale'
    UNION ALL
    SELECT
        bp.date::DATE,
        bp.city_group,
        NULL::TEXT AS flow_event,
        'Tenants PWA' AS mkt_origin,
        bp.mkt_channel,
        bp.mkt_medium,
        bp.mkt_source,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS utm_campaign,
        bp.context AS campaign_context,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS sk_sale_flow,
        NULL::INT AS sk_buyer,
        NULL::INT AS sk_house,
        NULL::DATE AS dt_booking_created,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        NULL::FLOAT AS budget,
        bp.nbp_target::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        NULL::FLOAT AS marketing_cost
    FROM
        datalake_raw.gsheets_sale_nbp_source_targets AS bp
    UNION ALL
    SELECT
        date::DATE,
        city_group,
        NULL::TEXT AS flow_event,
        'Tenants PWA' AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS utm_campaign,
        'Sale' AS campaign_context,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS sk_sale_flow,
        NULL::INT AS sk_buyer,
        NULL::INT AS sk_house,
        NULL::DATE AS dt_booking_created,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        sf_target::FLOAT AS sale_flows_target,
        NULL::FLOAT AS marketing_cost
    FROM
        datalake_raw.gsheets_sale_flows_targets
),
----------------------------------------------------------------------------------------------------------------------------
-- Query Performance Marketing Investment ForSale Demand costs (mkt_origin = 'Tenants PWA') and introduce NULLs for UNION --
----------------------------------------------------------------------------------------------------------------------------
investment AS (
    SELECT
        dd.date,
        city_group,
        NULL::TEXT AS flow_event,
        'Tenants PWA' AS mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        campaign_name,
        utm_campaign,
        'Sale' AS campaign_context,
        utm_term,
        utm_content,
        NULL::TEXT AS sk_sale_flow,
        NULL::INT AS sk_buyer,
        NULL::INT AS sk_house,
        NULL::DATE AS dt_booking_created,
        NULL::INT AS sk_booking,
        NULL::DATE AS dt_offer_submitted,
        NULL::TEXT AS sk_offer,
        NULL::INT AS sale_flow_order,
        NULL::INT AS buyer_prospect_order,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS new_buyer_prospects_target,
        NULL::FLOAT AS sale_flows_target,
        SUM(co.cost::FLOAT) AS marketing_cost
    FROM
        marketing.fact_marketing_daily_costs AS co
    JOIN dim_date AS dd
        ON dd.sk_date = co.sk_date
    WHERE
        co.mkt_origin = 'Tenants PWA - Sale'
        AND dd.date >= DATE('2020-01-01')
        AND co.mkt_medium != 'Branding'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
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