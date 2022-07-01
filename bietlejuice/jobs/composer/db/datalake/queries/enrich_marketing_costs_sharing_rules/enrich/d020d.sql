WITH
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
        dw_public.fact_listing_rent_flows AS lrf
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
        dw_public.fact_listing_rent_flows AS lrf
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
		dw_datamarts_cross.talk_to_agent AS tta
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
    WHERE
		rgn.short_region_name = 'SP'
	    AND tp.mkt_medium = 'SEM branded'
		AND tp.mkt_source = 'Google'
)
SELECT
    adt.id_date,
    tp.city_group,
    FLOAT(COUNT(DISTINCT tp.sk_client)/NULLIF(SUM(COUNT(DISTINCT tp.sk_client)) OVER(PARTITION BY adt.id_date), 0)) AS share,
	'demand' AS funnel_side
FROM
    tenant_prospects AS tp
INNER JOIN
	datalake_quintoandar.aux_date AS adt
		ON DATE(tp.ts_interaction) = adt.date
WHERE
    tp.interactions_order = 1
GROUP BY
    1,2