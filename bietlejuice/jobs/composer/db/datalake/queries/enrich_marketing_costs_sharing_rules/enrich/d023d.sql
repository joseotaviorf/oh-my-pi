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
------------------------------------------------------------------------------
-- Order Tenant Prospects events by timestamp to extract only the first one --
------------------------------------------------------------------------------
tenant_prospects AS (
	SELECT
		tpe.sk_client,
		tpe.sk_region,
		tpe.mkt_medium,
		tpe.mkt_source,
		tpe.ts_interaction,
		rgn.city_group,
		ROW_NUMBER() OVER(PARTITION BY tpe.sk_client ORDER BY tpe.ts_interaction) AS interactions_order
	FROM
	    tenant_prospect_events AS tpe
	INNER JOIN
		datalake_region.region AS rgn
			ON rgn.id = tpe.sk_region
	WHERE
		rgn.city_group IN ('Brasília', 'Recife', 'Salvador')
		AND tpe.mkt_medium = 'Display'
		AND tpe.mkt_source = 'Facebook'
),
date_region_cross_join AS (
    SELECT
        adt.date,
		adt.id_date,
        rgn.city_group,
		1/COUNT(rgn.city_group) OVER(PARTITION BY adt.date) AS default_share
    FROM
        datalake_quintoandar.aux_date AS adt, datalake_region.region AS rgn
	WHERE
		rgn.city_group IN ('Brasília', 'Recife', 'Salvador')
	GROUP BY 1,2,3
)
SELECT
    drc.id_date,
    drc.city_group,
    COALESCE(
		COUNT(DISTINCT tp.sk_client)/NULLIF(SUM(COUNT(DISTINCT tp.sk_client)) OVER(PARTITION BY drc.id_date), 0),
		MAX(drc.default_share)
	) AS share,
	'demand' AS funnel_side
FROM
	date_region_cross_join AS drc
LEFT JOIN
	tenant_prospects AS tp
		ON drc.date=DATE(tp.ts_interaction)
        AND drc.city_group=tp.city_group
        AND tp.interactions_order = 1
GROUP BY
    1,2
