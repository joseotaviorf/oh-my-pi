WITH
-----------------------------------------------------------
----- CTE to fetch information from listing rent flow -----
-----------------------------------------------------------
rent_flow_client_info AS (
    SELECT DISTINCT
        COALESCE(house.id_region, -1) AS sk_region,
        COALESCE(rent_flow.id_visit, -1) AS sk_visit,
        COALESCE(dim_offer.sk_offer, -1) AS sk_offer,
        COALESCE(rent_flow.id_client, -1) AS sk_client
    FROM
        datalake_ebdb_rent_flow.rent_flow
    JOIN
        dw_rent.dim_house_listing
    ON
        dim_house_listing.id_house = rent_flow.id_house
        AND COALESCE(rent_flow.dt_rent_flow_created, '1900-01-01')
            BETWEEN COALESCE(dim_house_listing.ts_listing_version_start, '1900-01-01') AND COALESCE(dim_house_listing.ts_listing_version_end, NOW())
    LEFT JOIN
        datalake_ebdb_listing.house
    ON
        dim_house_listing.id_house = house.id
    LEFT JOIN
        datalake_visit.visits
    ON
        visits.id_visit = rent_flow.id_visit
    LEFT JOIN
        dw_rent.dim_offer
    ON
        dim_offer.sk_offer = COALESCE(rent_flow.id_offer_context, -1)
        AND dim_offer.sk_offer != -1
    WHERE
        dim_house_listing.is_for_rent
        AND (
            COALESCE(visits.business_context, '') <> 'SALE'
            OR (visits.business_context = 'SALE' AND rent_flow.id_contract IS NOT NULL)
        )
),
cross_channel AS (
	SELECT
		visit_code,
		event_name,
		final_attribution_app_type,
		final_attribution_media_source,
		final_attribution_source,
		final_attribution_medium,
		final_attribution_campaign,
		final_attribution_content,
		final_attribution_term,
		final_attribution_branded,
		final_attribution_origin
  	FROM
    	datalake_tracked_events.attribution_cross_channel
	QUALIFY
		ROW_NUMBER() OVER (PARTITION BY visit_code ORDER BY ts_event DESC) = 1
),
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
tenant_prospect_events AS (
	SELECT
		lrf.sk_client,
		lrf.sk_region,
		IF(acc.visit_code IS NOT NULL, acc.final_attribution_campaign, src.utm_campaign) AS utm_campaign,
		v.ts_created AS ts_interaction
	FROM
		datalake_visit.visits AS v
	INNER JOIN
        rent_flow_client_info AS lrf
			ON v.id_visit = lrf.sk_visit
	LEFT JOIN
    	datalake_amplitude_visit.amplitude_visit AS src
        	ON v.code = src.id_visit
	LEFT JOIN
		cross_channel AS acc
			ON v.code = acc.visit_code
			AND acc.event_name IN ('visit_schedule_confirmed','debug_visit_schedule_confirmed')
	WHERE
		v.business_context = 'RENT'
    UNION ALL
	SELECT
		lrf.sk_client,
		lrf.sk_region,
		dof.utm_campaign,
		dof.dt_first_sent AS ts_interaction
	FROM
		dw_rent.dim_offer AS dof
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
		tta.utm_campaign,
		TIMESTAMP(tta.first_message_ts) AS ts_interaction
	FROM
		datalake_talk_to_agent.talk_to_agent AS tta
	INNER JOIN
        dw_rent.fact_house_listings AS fhl
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
		tpe.utm_campaign,
		tpe.ts_interaction,
		rgn.city_group,
		ROW_NUMBER() OVER(PARTITION BY tpe.sk_client ORDER BY tpe.ts_interaction) AS interactions_order
	FROM
	    tenant_prospect_events AS tpe
	INNER JOIN
    	datalake_region.region AS rgn
        	ON rgn.id = tpe.sk_region
),
----------------------------------------------------------------------------
-- In case of get 0 results on that day a fall back share will be applied --
----------------------------------------------------------------------------
fall_back(city_group, share) AS (
    SELECT 'RMSP', 0.50 UNION ALL
    SELECT 'Rio de Janeiro', 0.17 UNION ALL
    SELECT 'Porto Alegre', 0.07 UNION ALL
    SELECT 'Belo Horizonte', 0.12 UNION ALL
    SELECT 'Ribeirão Preto', 0.03 UNION ALL
    SELECT 'Santos', 0.05 UNION ALL
    SELECT 'Brasília', 0.02 UNION ALL
    SELECT 'Campinas', 0.04
),
fall_back_dated AS (
	SELECT
		adt.id_date,
		'{id_rule}' AS id_rule,
		city_group,
		share,
		'demand' AS funnel_side
	FROM fall_back AS fb
	CROSS JOIN datalake_quintoandar.aux_date AS adt
),
---------------------------------------------------------
-- Getting the real share based on the previous result --
---------------------------------------------------------
real AS (
	SELECT
		adt.id_date,
		'{id_rule}' AS id_rule,
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
		AND tp.utm_campaign = 'd039d.D.ACQ.Rent.App.Activation.Android.Firebase'
		AND tp.city_group IN ('RMSP', 'Rio de Janeiro', 'Porto Alegre', 'Belo Horizonte', 'Ribeirão Preto', 'Santos', 'Brasília', 'Campinas')
	GROUP BY
		1,2,3
),
-------------------------------------------------------------------------------------------
-- Creating a validator metric that will set which table the share value will come from --
-------------------------------------------------------------------------------------------
validacao AS (
SELECT
	adt.id_date,
	COUNT(DISTINCT sk_client) AS validador
FROM datalake_quintoandar.aux_date AS adt
LEFT JOIN
	tenant_prospects AS tp
		ON DATE(tp.ts_interaction) = adt.date
		AND tp.interactions_order = 1
		AND tp.utm_campaign = 'd039d.D.ACQ.Rent.App.Activation.Android.Firebase'
  		AND tp.city_group IN ('RMSP', 'Rio de Janeiro', 'Porto Alegre', 'Belo Horizonte', 'Ribeirão Preto', 'Santos', 'Brasília', 'Campinas')
GROUP BY 1
)
-------------------------------------------------------------------------------------------------------
-- Applying share factor from the correct table based on status: it has or hasn't result on that day --
-------------------------------------------------------------------------------------------------------
SELECT DISTINCT
	v.id_date,
	'{id_rule}' AS id_rule,
	CASE
		WHEN validador > 0 THEN r.city_group
		ELSE fb.city_group
	END AS city_group,
	CASE
		WHEN validador > 0 THEN r.share
		ELSE fb.share
	END AS share,
	'demand' AS funnel_side,
	CAST(NULL AS STRING) AS business_context
FROM validacao v
LEFT JOIN real AS r
	ON r.id_date = v.id_date
LEFT JOIN fall_back_dated AS fb
	ON fb.id_date = v.id_date
