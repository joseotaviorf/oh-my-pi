WITH
--------------------------------------------------------------------------------------------------------------------
-- Query bookings, offers and talk to agent full history to rank events, users and rent_flows as new or recurrent --
--------------------------------------------------------------------------------------------------------------------
booking AS (
    SELECT
        flrf.sk_client,
        a.id_property,
        flrf.sk_region,
        a.mkt_origin,
        a.mkt_channel,
        a.mkt_medium,
        a.mkt_source,
        a.utm_campaign,
        a.dt_created,
        a.sk_booking,
        ROW_NUMBER() OVER(PARTITION BY sk_client
                          ORDER BY a.dt_created) AS rk_booking
    FROM
        dim_booking a
    join fact_listing_rent_Flows flrf
        using(sk_booking)
    WHERE
        a.sk_booking > 0
        AND a.visit_intent = 'RENT'
        AND a.type = 'Visita'
),
offer AS (
    SELECT
        flrf.sk_client,
        a.id_property,
        flrf.sk_region,
        a.mkt_origin,
        a.mkt_channel,
        a.mkt_medium,
        a.mkt_source,
        a.utm_campaign,
        a.dt_first_sent,
        a.sk_offer,
        ROW_NUMBER() OVER(PARTITION BY sk_client
                          ORDER BY a.dt_created) AS rk_offer
    FROM
        dim_offer AS a
    JOIN fact_listing_rent_flows AS flrf
        USING(sk_offer)
    WHERE
        a.sk_offer > 0
),
talk_to_agent AS (
	SELECT
	    tenant_id::int AS sk_client,
	    house_id::int,
	    fhl.sk_region,
	    a.mkt_origin,
	    a.mkt_channel,
	    a.mkt_medium,
	    a.mkt_source,
	    a.utm_campaign,
        a.first_message_ts::timestamp,
        a.sk_house_listing || a.tenant_id || a.agent_id AS sk_tta,
		ROW_NUMBER() OVER(PARTITION BY sk_client
		                  ORDER BY first_message_ts) AS rk_tta
	FROM
	    datamarts.talk_to_agent AS a
    JOIN fact_house_listings AS fhl
        ON a.sk_house_listing = fhl.sk_house_listing
    WHERE
        a.business_context = 'RENT'
),
----------------------------------------------------------------------------------------------------------------------
-- Merge activation events (offer, booking and talk to agent) and order them by user and rent_flows (user || house) --
----------------------------------------------------------------------------------------------------------------------
rent_flows_raw AS (
    SELECT
    	evt.*,
    	dr.city_group,
        ROW_NUMBER() OVER(PARTITION BY evt.client, evt.id_house
                          ORDER BY evt.ts_event) AS rk_rf,
        ROW_NUMBER() OVER(PARTITION BY evt.client
                          ORDER BY evt.ts_event) AS rk_tp
    FROM (
    	SELECT
	        DATE(b.dt_created) AS dt_event,
	        b.dt_created AS ts_event,
	        b.sk_client AS client,
	        b.id_property AS id_house,
	        b.sk_region,
	        b.mkt_origin AS mkt_origin,
	        b.mkt_channel AS mkt_channel,
	        b.mkt_medium AS mkt_medium,
	        b.mkt_source AS mkt_source,
	        b.utm_campaign AS utm_campaign,
	        'Booking' AS event_type,
	        b.sk_booking,
	        b.rk_booking,
	        NULL AS sk_offer,
	        NULL AS rk_offer,
	        NULL AS sk_tta,
	        NULL AS rk_tta
	    FROM booking AS b

	    UNION ALL

	    SELECT
			DATE(o.dt_first_sent) AS dt_event,
			o.dt_first_sent AS ts_event,
			o.sk_client AS client,
			o.id_property AS id_house,
			o.sk_region,
			o.mkt_origin AS mkt_origin,
			o.mkt_channel AS mkt_channel,
			o.mkt_medium AS mkt_medium,
			o.mkt_source AS mkt_source,
			o.utm_campaign AS utm_campaign,
			'Offer' AS event_type,
			NULL AS sk_booking,
			NULL AS rk_booking,
			o.sk_offer,
			o.rk_offer,
			NULL AS sk_tta,
			NULL AS rk_tta
	    FROM offer AS o

	    UNION ALL

	   	SELECT
		    DATE(tta.first_message_ts) AS dt_event,
		    tta.first_message_ts AS ts_event,
		    tta.sk_client AS client,
		    tta.house_id AS id_house,
		    tta.sk_region,
		    tta.mkt_origin AS mkt_origin,
		    tta.mkt_channel AS mkt_channel,
		    tta.mkt_medium AS mkt_medium,
		    tta.mkt_source AS mkt_source,
		    tta.utm_campaign AS utm_campaign,
		    'Talk to Agent' AS event_type,
		    NULL AS sk_booking,
		    NULL AS rk_booking,
		    NULL AS sk_offer,
		    NULL AS rk_offer,
		    tta.sk_tta,
		    tta.rk_tta
	    FROM talk_to_agent AS tta
    ) AS evt
    JOIN dim_region AS dr
        ON evt.sk_region = dr.sk_region
),
-----------------------------------------------------------------------------------
-- Consolidate new rent_flows, new tenant prospects, new events and total events --
-----------------------------------------------------------------------------------
rent_flows AS (
    SELECT
        rf.dt_event,
        rf.event_type,
        rf.city_group,
        rf.mkt_origin,
        rf.mkt_channel,
        rf.mkt_medium,
        rf.mkt_source,
        rf.utm_campaign,
	    '' as campaign_name,
        COUNT(DISTINCT CASE WHEN rf.rk_rf = 1 THEN rf.client || rf.id_house ELSE NULL END) AS new_rent_flows,
        COUNT(DISTINCT CASE WHEN rf.rk_tp = 1 THEN rf.client ELSE NULL END) AS new_tenant_prospects,
        COUNT(DISTINCT rf.client) AS tenant_prospects,
        COUNT(DISTINCT rf.sk_booking) AS visits_booked,
        COUNT(DISTINCT CASE WHEN rf.rk_booking = 1 THEN rf.sk_booking ELSE NULL END) AS first_bookings,
        COUNT(DISTINCT rf.sk_offer) AS offer_sent,
        COUNT(DISTINCT CASE WHEN rf.rk_offer = 1 THEN rf.sk_offer ELSE NULL END) AS first_offer_sent,
        COUNT(DISTINCT rf.sk_tta) AS talk_to_agent,
        COUNT(DISTINCT CASE WHEN rf.rk_tta = 1 THEN rf.sk_tta ELSE NULL END) AS first_talk_to_agent
    FROM
        rent_flows_raw rf
    WHERE
        rf.dt_event >= current_date - interval '12 month'
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
-------------------------------------------------------------------------------------------------
-- Query Performance Marketing Investment for Rental Demand costs (mkt_origin = 'Tenants PWA') --
-------------------------------------------------------------------------------------------------
demand_daily_spent AS (
    SELECT
        dd.date,
        co.city_group,
        '' AS event_type,
        co.mkt_origin,
        co.mkt_channel,
        co.mkt_medium,
        co.mkt_source,
	    '' as utm_campaign,
        campaign_name,
        SUM(co.cost::FLOAT) AS spent
    FROM
        marketing.fact_marketing_daily_costs AS co
    JOIN dim_date dd
        ON dd.sk_date = co.sk_date
    WHERE
        co.mkt_origin = 'Tenants PWA'
        AND dd.date >= current_date - interval '12 month'
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
-------------------------------------------------------
-- Query Performance Marketing Rental Demand targets --
-------------------------------------------------------
demand_daily_targets AS (
    SELECT
        str.date::date,
        str.city_group,
        '' AS event_type,
        'Tenants PWA' AS mkt_origin,
        str.mkt_channel,
        str.mkt_medium,
        '' AS mkt_source,
        '' AS utm_campaign,
        '' AS campaign_name,
        SUM(NULLIF(budget,'')) AS budget,
        SUM(NULLIF(visits_booked_target, '')) AS visits_booked_target,
        SUM(NULLIF(offer_sent_target, '')) AS offer_sent_target,
        SUM(NULLIF(first_offer_sent_target, '')) AS first_offer_sent_target,
        SUM(NULLIF(new_rent_flows_target, '')) AS new_rent_flows_target,
        SUM(NULLIF(new_tenant_prospects_target, '')) AS new_tenant_prospects_target
    FROM
        datalake_raw.gsheets_demand_targets_replanning AS str
    WHERE
        str.date::DATE >= current_date - interval '12 month'
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
-----------------------
-- Concat all tables --
-----------------------
base as (
    SELECT
    	rf.dt_event,
    	rf.city_group,
    	rf.event_type,
    	rf.mkt_origin,
    	rf.mkt_channel,
    	rf.mkt_medium,
    	rf.mkt_source,
    	rf.utm_campaign,
    	rf.campaign_name,
        rf.visits_booked,
        rf.first_bookings,
        rf.offer_sent,
        rf.first_offer_sent,
        rf.talk_to_agent,
        rf.first_talk_to_agent,
        rf.new_rent_flows,
        rf.new_tenant_prospects,
        rf.tenant_prospects,
        0.0 AS spent,
        0.0 AS visits_booked_target,
        0.0 AS offer_sent_target,
        0.0 AS first_offer_sent_target,
        0.0 AS new_rent_flows_target,
        0.0 AS new_tenant_prospects_target,
        0.0 AS budget
    FROM
        rent_flows AS rf

    UNION ALL

    SELECT
    	dds.date,
    	dds.city_group,
    	dds.event_type,
    	dds.mkt_origin,
    	dds.mkt_channel,
    	dds.mkt_medium,
    	dds.mkt_source,
    	dds.utm_campaign,
    	dds.campaign_name,
        0.0 AS visits_booked,
        0.0 AS first_bookings,
        0.0 AS offer_sent,
        0.0 AS first_offer_sent,
        0.0 AS talk_to_agent,
        0.0 AS first_talk_to_agent,
        0.0 AS new_rent_flows,
        0.0 AS new_tenant_prospects,
        0.0 AS tenant_prospects,
        dds.spent,
        0.0 AS visits_booked_target,
        0.0 AS offer_sent_target,
        0.0 AS first_offer_sent_target,
        0.0 AS new_rent_flows_target,
        0.0 AS new_tenant_prospects_target,
        0.0 AS budget
    FROM
        demand_daily_spent AS dds

    UNION ALL

    SELECT
    	ddt.date,
    	ddt.city_group,
    	ddt.event_type,
    	ddt.mkt_origin,
    	ddt.mkt_channel,
    	ddt.mkt_medium,
    	ddt.mkt_source,
    	ddt.utm_campaign,
    	ddt.campaign_name,
        0.0 AS visits_booked,
        0.0 AS first_bookings,
        0.0 AS offer_sent,
        0.0 AS first_offer_sent,
        0.0 AS talk_to_agent,
        0.0 AS first_talk_to_agent,
        0.0 AS new_rent_flows,
        0.0 AS new_tenant_prospects,
        0.0 AS tenant_prospects,
        0.0 AS spent,
        ddt.visits_booked_target,
        ddt.offer_sent_target,
        ddt.first_offer_sent_target,
        ddt.new_rent_flows_target,
        ddt.new_tenant_prospects_target,
        ddt.budget
    FROM
        demand_daily_targets AS ddt
)
-----------------------------------------------------
-- Group everything to avoid duplicated dimensions --
-----------------------------------------------------
SELECT
    b.dt_event,
    b.city_group,
    b.event_type,
    b.mkt_origin,
    b.mkt_channel,
    b.mkt_medium,
    b.mkt_source,
    b.utm_campaign,
    b.campaign_name,
    SUM(b.visits_booked) AS visits_booked,
    SUM(b.first_bookings) AS first_bookings,
    SUM(b.offer_sent) AS offer_sent,
    SUM(b.first_offer_sent) AS first_offer_sent,
    SUM(b.talk_to_agent) AS talk_to_agent,
    SUM(b.first_talk_to_agent) AS first_talk_to_agent,
    SUM(b.new_rent_flows) AS new_rent_flows,
    SUM(b.new_tenant_prospects) AS new_tenant_prospects,
    SUM(b.tenant_prospects) AS tenant_prospects,
    SUM(b.spent) AS spent,
    SUM(b.visits_booked_target) AS visits_booked_target,
    SUM(b.offer_sent_target) AS offer_sent_target,
    SUM(b.first_offer_sent_target) AS first_offer_sent_target,
    SUM(b.new_rent_flows_target) AS new_rent_flows_target,
    SUM(b.new_tenant_prospects_target) AS new_tenant_prospects_target,
    SUM(b.budget) AS budget
FROM
	base AS b
GROUP BY 1,2,3,4,5,6,7,8,9