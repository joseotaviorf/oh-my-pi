WITH
----------------------------------------------------------------
-- CTE to fetch information from clients in listing rent flow --
----------------------------------------------------------------
rent_flow_client_info AS (
    SELECT DISTINCT
        COALESCE(house.id_region, -1) AS sk_region,
        COALESCE(rent_flow.id_booking, -1) AS sk_booking,
        COALESCE(dim_offer.sk_offer, -1) AS sk_offer,
        COALESCE(rent_flow.id_client, -1) AS sk_client
    FROM
        datalake_ebdb_rent_flow.rent_flow
    JOIN
        dw_public.dim_house_listing
    ON
        dim_house_listing.id_house = rent_flow.id_house
        AND COALESCE(rent_flow.dt_rent_flow_created, '1900-01-01')
            BETWEEN COALESCE(dim_house_listing.ts_listing_version_start, '1900-01-01') AND COALESCE(dim_house_listing.ts_listing_version_end, NOW())
    LEFT JOIN
        datalake_ebdb_listing.house
    ON
        dim_house_listing.id_house = house.id
    LEFT JOIN
        dw_public.dim_booking
    ON
        dim_booking.sk_booking = rent_flow.id_booking
    LEFT JOIN
        dw_public.dim_offer
    ON
        dim_offer.sk_offer = COALESCE(rent_flow.id_offer_context, -1)
        AND dim_offer.sk_offer != -1
    WHERE
        dim_house_listing.is_for_rent
        AND (
            COALESCE(dim_booking.visit_intent, '') <> 'SALE'
            OR (dim_booking.visit_intent = 'SALE' AND rent_flow.id_contract IS NOT NULL)
        )
),
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
tenant_prospect_events AS (
	SELECT
		lrf.sk_client,
		lrf.sk_region,
		dbk.mkt_medium,
		dbk.mkt_source,
		dbk.dt_created AS ts_interaction
	FROM
		dw_public.dim_booking AS dbk
	INNER JOIN
        rent_flow_client_info AS lrf
        	USING(sk_booking)
	WHERE
		dbk.sk_booking > 0
		AND dbk.visit_intent = 'RENT'
		AND dbk.type = 'Visita'
		AND dbk.dt_created IS NOT NULL
    UNION ALL
	SELECT
		lrf.sk_client,
		lrf.sk_region,
		dof.mkt_medium,
		dof.mkt_source,
		dof.dt_first_sent AS ts_interaction
	FROM
		dw_public.dim_offer AS dof
	INNER JOIN
        rent_flow_client_info AS lrf
	        USING(sk_offer)
	WHERE
		dof.sk_offer > 0
		AND dof.dt_first_sent IS NOT NULL
    UNION ALL
	SELECT
		INT(tenant_id) AS sk_client,
		fhl.sk_region,
		tta.mkt_medium,
		tta.mkt_source,
		TIMESTAMP(tta.first_message_ts) AS ts_interaction
	FROM
		datalake_talk_to_agent.talk_to_agent AS tta
	INNER JOIN
        dw_public.fact_house_listings AS fhl
            USING(sk_house_listing)
	WHERE
		tta.business_context = 'RENT'
		AND tta.first_message_ts IS NOT NULL
),
----------------------------------------------------------------------------------------------------------------------
-- Merge activation events (offer, booking and talk to agent) and order them by user and rent_flows (user || house) --
----------------------------------------------------------------------------------------------------------------------
tenant_prospects AS (
	SELECT
		tpe.sk_client,
		tpe.sk_region,
		tpe.mkt_medium,
		tpe.mkt_source,
		tpe.ts_interaction,
		rgn.short_region_name,
		rgn.city_group,
		ROW_NUMBER() OVER(PARTITION BY tpe.sk_client ORDER BY tpe.ts_interaction) AS interactions_order
	FROM
	    tenant_prospect_events AS tpe
	INNER JOIN
    	datalake_region.region AS rgn
        	ON rgn.id = tpe.sk_region
)
SELECT
	adt.id_date,
	'{id_rule}' AS id_rule,
	tp.city_group,
	FLOAT(COUNT(DISTINCT tp.sk_client)/NULLIF(SUM(COUNT(DISTINCT tp.sk_client)) OVER(PARTITION BY adt.id_date), 0)) AS share,
	'demand' AS funnel_side,
	CAST(NULL AS STRING) AS business_context
FROM
	tenant_prospects AS tp
INNER JOIN
	datalake_quintoandar.aux_date AS adt
		ON DATE(tp.ts_interaction) = adt.date
WHERE
	tp.interactions_order = 1
	AND tp.short_region_name = 'SP'
	AND tp.mkt_medium = 'SEM branded'
	AND tp.mkt_source = 'Google'
GROUP BY
	1,2,3
