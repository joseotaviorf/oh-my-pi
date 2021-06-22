-----------------------------------------------------------------------------------
-- This datamart seeks to consolidate marketing investment and results generated --
-- by campaign and business context, ForRental (fr) or ForSale (fs)              --
-----------------------------------------------------------------------------------
WITH
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
booking AS (
    SELECT
        flrf.sk_client,
        flrf.sk_region,
        a.mkt_category,
        a.mkt_flow,
        a.mkt_completion,
        a.mkt_origin,
        a.mkt_channel,
        a.mkt_medium,
        a.mkt_source,
        a.utm_campaign,
        a.dt_created AS ts_event
    FROM
        dim_booking AS a
        JOIN
            fact_listing_rent_Flows flrf
            USING(sk_booking)
    WHERE
        a.sk_booking > 0
        AND a.visit_intent = 'RENT'
        AND a.type = 'Visita'
        AND a.dt_created IS NOT NULL
),
offer AS (
    SELECT
        flrf.sk_client,
        flrf.sk_region,
        a.mkt_category,
        a.mkt_flow,
        a.mkt_completion,
        a.mkt_origin,
        a.mkt_channel,
        a.mkt_medium,
        a.mkt_source,
        a.utm_campaign,
        a.dt_first_sent AS ts_event
    FROM
        dim_offer AS a
        JOIN fact_listing_rent_flows AS flrf
            USING(sk_offer)
    WHERE
        a.sk_offer > 0
        AND a.dt_first_sent IS NOT NULL
),
talk_to_agent AS (
    SELECT
        tenant_id::INT AS sk_client,
        fhl.sk_region,
        a.mkt_category,
        a.mkt_flow,
        a.mkt_completion,
        a.mkt_origin,
        a.mkt_channel,
        a.mkt_medium,
        a.mkt_source,
        a.utm_campaign,
        a.first_message_ts::timestamp AS ts_event
    FROM
        datamarts.talk_to_agent AS a
        JOIN fact_house_listings AS fhl
            ON a.sk_house_listing = fhl.sk_house_listing
    WHERE
        a.business_context = 'RENT'
        AND a.first_message_ts IS NOT NULL
),
----------------------------------------------------------------------------------------------------------------------
-- Merge activation events (offer, booking and talk to agent) and order them by user and rent_flows (user || house) --
----------------------------------------------------------------------------------------------------------------------
rent_flows_raw AS (
    SELECT
        evt.*,
        DATE(evt.ts_event) AS dt_event,
        dr.city_group,
        ROW_NUMBER() OVER(PARTITION BY evt.sk_client
                                            ORDER BY evt.ts_event) AS tenant_prospect_order
    FROM (
        SELECT
            b.*
        FROM
            booking AS b

        UNION ALL

        SELECT
            o.*
        FROM
            offer AS o

        UNION ALL

        SELECT
            tta.*
        FROM
            talk_to_agent AS tta
    ) AS evt
        JOIN dim_region AS dr
            ON evt.sk_region = dr.sk_region
),
---------------------------------------------------------
-- Query qualifieds and listings ForRental and ForSale --
---------------------------------------------------------
qualifieds_fr AS (
    SELECT
        dd.sk_date,
        'qualifieds' AS event_type,
        COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        f.mkt_category,
        f.mkt_flow,
        f.mkt_completion,
        f.mkt_origin,
        f.mkt_channel,
        f.mkt_medium,
        f.mkt_source,
        dl.utm_campaign,
        COUNT(1) AS events_quantity_FR,
        0 AS events_quantity_FS
    FROM
        fact_house_listing_flows AS f
        JOIN dim_lead AS dl
            ON dl.sk_lead = f.sk_lead
        JOIN dim_region dr
            ON f.sk_region = dr.sk_region
        JOIN dim_date dd
            ON dd.sk_date = f.sk_qualified_date
    WHERE
        sk_qualified_date >= 20190101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
listings_fr AS (
    SELECT
        dd.sk_date,
        'listings' AS event_type,
        COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        f.mkt_category,
        f.mkt_flow,
        f.mkt_completion,
        f.mkt_origin,
        f.mkt_channel,
        f.mkt_medium,
        f.mkt_source,
        dl.utm_campaign,
        COUNT(1) AS events_quantity_fr,
        0 AS events_quantity_fs
    FROM
        fact_house_listing_flows AS f
        JOIN dim_lead AS dl
            ON dl.sk_lead = f.sk_lead
        JOIN dim_region dr
            ON f.sk_region = dr.sk_region
        JOIN dim_date dd
            ON dd.sk_date = f.sk_first_listing_date
    WHERE
        sk_first_listing_date >= 20190101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
qualifieds_fs AS (
    SELECT
        dd.sk_date,
        'qualifieds' AS event_type,
        COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        f.mkt_category,
        f.mkt_flow,
        f.mkt_completion,
        f.mkt_origin,
        f.mkt_channel,
        f.mkt_medium,
        f.mkt_source,
        dl.utm_campaign,
        0 AS events_quantity_FR,
        COUNT(1) AS events_quantity_FS
    FROM
        sale.fact_listing_flows AS f
        JOIN dim_lead dl
            ON dl.sk_lead = f.sk_lead
        JOIN dim_region dr
            ON f.sk_region = dr.sk_region
        JOIN dim_date dd
            ON dd.sk_date = f.sk_qualified_date
    WHERE
        sk_qualified_date >= 20190101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
listings_fs AS (
    SELECT
        dd.sk_date,
        'listings' AS event_type,
        COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        f.mkt_category,
        f.mkt_flow,
        f.mkt_completion,
        f.mkt_origin,
        f.mkt_channel,
        f.mkt_medium,
        f.mkt_source,
        dl.utm_campaign,
        0 AS events_quantity_FR,
        COUNT(1) AS events_quantity_FS
    FROM
        sale.fact_listing_flows AS f
        JOIN dim_lead AS dl
            ON dl.sk_lead = f.sk_lead
        JOIN dim_region AS dr
            ON f.sk_region = dr.sk_region
        JOIN dim_date dd
            ON dd.sk_date = f.sk_first_listing_date
    WHERE
        sk_first_listing_date >= 20190101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
supply_funnel AS (
    SELECT
        *
    FROM
        qualifieds_fr
    --
    UNION ALL
    SELECT
        *
    FROM
        qualifieds_fs

    UNION ALL 

    SELECT
        *
    FROM
        listings_fr

    UNION ALL

    SELECT
        *
    FROM
        listings_fs
),
----------------------------------------------------------------------------------------------
-- Query affiliates and weights for each city_group based on qualifieds from previous month --
----------------------------------------------------------------------------------------------
rental_affiliates_qualifieds AS (
    SELECT
        add_months(dd.month_start, 1) AS month_start,
        dr.city_group,
        COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 THEN sk_house_listing_flow ELSE NULL END) AS qualifieds_rent
    FROM 
        fact_house_listing_flows AS rf
        JOIN dim_date AS dd
            ON dd.sk_date = rf.sk_qualified_date
        JOIN dim_region AS dr
            USING(sk_region)
    WHERE
        rf.sk_qualified_date > 20181201
        AND rf.mkt_origin IN ('Indica Aí - General','Doorman','Indica Aí - Agents')
        AND dr.city_group IS NOT NULL 
    GROUP BY 1,2
),
sale_affiliates_qualifieds AS (
    SELECT
        add_months(dd.month_start, 1) AS month_start,
        dr.city_group,
        COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 THEN sk_house_listing_flow ELSE NULL END) AS qualifieds_sale
    FROM 
        sale.fact_listing_flows as sf
        JOIN dim_date AS dd
            ON dd.sk_date = sf.sk_qualified_date
        JOIN dim_region AS dr
            USING(sk_region)
    WHERE
        sf.sk_qualified_date > 20181201
        AND sf.mkt_origin IN ('Indica Aí - General','Doorman','Indica Aí - Agents')
        AND dr.city_group IS NOT NULL 
    GROUP BY 1,2
),
affiliates_proportion AS (
    SELECT
        COALESCE(r.month_start, s.month_start) AS month,
        COALESCE(r.city_group, s.city_group) AS city_group,
        COALESCE(qualifieds_rent / NULLIF(SUM(qualifieds_rent::FLOAT + COALESCE(qualifieds_sale, 0)::FLOAT) OVER(PARTITION BY MONTH), 0), 0) AS prop_rent,
        COALESCE(qualifieds_sale / NULLIF(SUM(qualifieds_rent::FLOAT + COALESCE(qualifieds_sale, 0)::FLOAT) OVER(PARTITION BY MONTH), 0), 0) AS prop_sale
    FROM
        rental_affiliates_qualifieds AS r
        FULL OUTER JOIN sale_affiliates_qualifieds AS s
            ON r.month_start = s.month_start
            AND r.city_group = s.city_group
),
affiliates AS (
    SELECT
        dd.sk_date,
        dd.month_start,
        'Affiliates' AS event_type,
        '' AS mkt_category,
        '' AS mkt_flow,
        '' AS mkt_completion,
        dua.mkt_origin,
        dua.mkt_channel,
        dua.mkt_medium,
        dua.mkt_source,
        dua.tracking_campaign AS utm_campaign,
        COUNT(DISTINCT dua.sk_user) AS event_quantity
    FROM 
        dim_user_affiliate AS dua
        JOIN dim_date AS dd
            ON date(dua.ts_joined_program) = dd.date
    WHERE
        sk_date >= 20190101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
---------------------------
-- Query marketing costs --
---------------------------
online_costs AS (
    SELECT
        sk_date,
        funnel_side,
        city_group,
        mkt_category,
        mkt_flow,
        mkt_completion,
        REPLACE(COALESCE(mkt_origin, ''), ' - Sale', '') AS mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        utm_campaign,
        SUM(CASE WHEN mkt_origin ~* ' \- sale' THEN 0::FLOAT ELSE cost END) AS cost_fr,
        SUM(CASE WHEN mkt_origin ~* ' \- sale' THEN cost ELSE 0::FLOAT END) AS cost_fs
    FROM marketing.fact_marketing_daily_costs
    WHERE
        sk_date >= 20190101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    HAVING
        cost_fr > 0
        OR cost_fs > 0
),
affiliate_costs AS (
    WITH
    ia_fact_affiliate_transposed AS (
        SELECT
            sk_date,
            'fact_affiliate' AS table,
            mkt_origin, city_group,
            'engagement' AS vertical,
            'Commission Listing' AS source,
            commission_listing AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date >= 20190101

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table,
            mkt_origin, city_group,
            'engagement' AS vertical,
            'Commission Rent' AS source,
            commission_rent AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date >= 20190101

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table,
            mkt_origin,
            city_group,
            'acquisition' AS vertical,
            'Commission MGM' AS source,
            commission_mgm AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date >= 20190101

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Commission Tradecom' AS source,
            commission_tradecom AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date >= 20190101

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Promotional Bonus' AS source,
            promotional_bonus AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date >= 20190101

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Notification' AS source,
            notification AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date >= 20190101

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Other' AS source,
            other AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date >= 20190101
    )
    SELECT
        sk_date,
        'affiliates' AS funnel_side,
        iac.city_group,
        NULL::TEXT AS mkt_category,
        NULL::TEXT AS mkt_flow,
        NULL::TEXT AS mkt_completion,
        iac.mkt_origin,
        iac.source AS mkt_channel,
        iac.source AS mkt_medium,
        iac.source AS mkt_source,
        NULL::TEXT AS utm_campaign,
        SUM(iac.cost::FLOAT) AS cost_fr,
        0::FLOAT AS cost_fs
    FROM
        ia_fact_affiliate_transposed AS iac
    WHERE 
        iac.cost IS NOT null
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    HAVING
        cost_fr > 0
),
branding_costs AS (
    SELECT
        sk_date::BIGINT,
        funnel_side,
        city_group,
        mkt_category,
        mkt_flow,
        mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        utm_campaign,
        SUM(CASE WHEN lower(trim(business_context)) = 'rent' THEN cost::FLOAT ELSE 0::FLOAT END) AS cost_fr,
        SUM(CASE WHEN lower(trim(business_context)) = 'sale' THEN cost::FLOAT ELSE 0::FLOAT END) AS cost_fs
    FROM datalake_raw.gsheets_offline_and_branding_marketing_costs
    WHERE
        sk_date >= 20190101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    HAVING
        cost_fr > 0
),
marketing_costs AS (
    SELECT *
    FROM
        affiliate_costs

    UNION ALL

    SELECT *
    FROM
        online_costs

    UNION ALL

    SELECT *
    FROM
        branding_costs
),
-----------------------
-- Concat everything --
-----------------------
marketing_campaigns_costs_and_volumes AS (
    SELECT
        TO_CHAR(dt_event, 'YYYYMMDD')::INT AS sk_date,
        'New Tenant Prospects' AS event_type,
        city_group,
        mkt_category,
        mkt_flow,
        mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        utm_campaign,
        NULL::TEXT AS cost_funnel_side,
        COUNT(DISTINCT CASE WHEN tenant_prospect_order = 1 THEN sk_client ELSE NULL END) AS events_quantity_fr,
        COUNT(NULL) AS events_quantity_fs,
        SUM(0::FLOAT) AS cost_fr,
        SUM(0::FLOAT) AS cost_fs
    FROM
        rent_flows_raw
    WHERE
        dt_event >= DATE('2019-01-01')
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

    UNION ALL

    SELECT
        sk_first_event_date AS sk_date,
        'New Buyer Prospect' AS event_type,
        dr.city_group,
        fsf.mkt_category,
        fsf.mkt_flow,
        fsf.mkt_completion,
        fsf.mkt_origin,
        fsf.mkt_channel,
        fsf.mkt_medium,
        fsf.mkt_source,
        fsf.utm_campaign,
        NULL::TEXT AS cost_funnel_side,
        COUNT(NULL) AS events_quantity_fr,
        COUNT(DISTINCT CASE WHEN fsf.is_buyer_first_sale_flow = 'True' THEN fsf.sk_buyer ELSE NULL END) AS events_quantity_fs,
        SUM(0::FLOAT) AS cost_fr,
        SUM(0::FLOAT) AS cost_fs
    FROM sale.fact_sale_flows AS fsf
        JOIN dim_region AS dr
            ON fsf.sk_region = dr.sk_region
    WHERE
        fsf.sk_first_event_date >= 20190101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

    UNION ALL

    SELECT
        sk_date,
        event_type,
        city_group,
        mkt_category,
        mkt_flow,
        mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        utm_campaign,
        NULL::TEXT AS cost_funnel_side,
        SUM(events_quantity_fr) AS events_quantity_fr,
        SUM(events_quantity_fs) AS events_quantity_fs,
        SUM(0::FLOAT) AS cost_fr,
        SUM(0::FLOAT) AS cost_fs
    from supply_funnel
    group by 1,2,3,4,5,6,7,8,9,10,11,12

    UNION ALL

    SELECT 
        a.sk_date,
        a.event_type,
        ap.city_group,
        a.mkt_category,
        a.mkt_flow,
        a.mkt_completion,
        a.mkt_origin,
        a.mkt_channel,
        a.mkt_medium,
        a.mkt_source,
        a.utm_campaign,
        NULL::TEXT AS cost_funnel_side,
        a.event_quantity * prop_rent::FLOAT AS events_quantity_fr,
        a.event_quantity * prop_sale::FLOAT AS events_quantity_fs,
        0::FLOAT AS cost_fr,
        0::FLOAT AS cost_fs
    FROM
        affiliates AS a
        LEFT JOIN affiliates_proportion AS ap
            ON a.month_start = ap.month

    UNION ALL

    SELECT
        sk_date,
        'Marketing Investment' AS event_type,
        city_group,
        mkt_category,
        mkt_flow,
        mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        utm_campaign,
        funnel_side AS cost_funnel_side,
        SUM(0::FLOAT) AS events_quantity_fr,
        SUM(0::FLOAT) AS events_quantity_fs,
        SUM(cost_fr) as cost_fr,
        SUM(cost_fs) as cost_fs
    FROM
        marketing_costs
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
)
---------------------------------------------------------------------------------------------
-- Group everything and "normalize" utm_campaign to make matching costs and results easier --
---------------------------------------------------------------------------------------------
SELECT
    sk_date,
    event_type,
    city_group,
    mkt_category,
    mkt_flow,
    mkt_completion,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    utm_campaign,
    REPLACE(REPLACE(utm_campaign, '-', '_'), '_', '.') AS utm_campaign_normalized,
    cost_funnel_side,
    SUM(events_quantity_fr) AS events_quantity_fr,
    SUM(events_quantity_fs) AS events_quantity_fs,
    SUM(cost_fr) AS cost_fr,
    SUM(cost_fs) AS cost_fs
FROM
    marketing_campaigns_costs_and_volumes
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13
