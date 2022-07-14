WITH
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
events AS (
	SELECT
		flrf.sk_client,
		flrf.sk_region,
		a.mkt_medium,
		a.mkt_source,
		a.dt_created AS ts_event
	FROM
		dim_booking AS a
	    INNER JOIN fact_listing_rent_Flows AS flrf
        	USING(sk_booking)
	WHERE
		a.sk_booking > 0
		AND a.visit_intent = 'RENT'
		AND a.type = 'Visita'
		AND a.dt_created IS NOT NULL
    UNION ALL
	SELECT
		flrf.sk_client,
		flrf.sk_region,
		a.mkt_medium,
		a.mkt_source,
		a.dt_first_sent AS ts_event
	FROM
		dim_offer AS a
	    JOIN fact_listing_rent_flows AS flrf
	        USING(sk_offer)
	WHERE
		a.sk_offer > 0
		AND a.dt_first_sent IS NOT NULL
    UNION ALL
	SELECT
		tenant_id::INT AS sk_client,
		fhl.sk_region,
		a.mkt_medium,
		a.mkt_source,
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
rent_flows AS (
	SELECT
		evt.*,
		DATE(evt.ts_event) AS dt_event,
		dr.short_region_name,
		dr.city_group,
		ROW_NUMBER() OVER(PARTITION BY evt.sk_client ORDER BY evt.ts_event) AS tenant_prospect_order
	FROM
	    events AS evt
	    JOIN dim_region AS dr
		    ON evt.sk_region = dr.sk_region
)
SELECT
    sk_date AS id_date,
    city_group,
    COUNT(DISTINCT sk_client) /
        NULLIF(SUM(COUNT(DISTINCT sk_client)) OVER(PARTITION BY sk_date), 0)::FLOAT AS share,
	'demand' AS funnel_side
FROM
    rent_flows AS rf
    JOIN dim_date AS dd
        ON dd.date = rf.dt_event
WHERE
    tenant_prospect_order = 1
    AND short_region_name = 'SP'
    AND mkt_medium = 'SEM branded'
	AND mkt_source = 'Google'
GROUP BY
    1,2