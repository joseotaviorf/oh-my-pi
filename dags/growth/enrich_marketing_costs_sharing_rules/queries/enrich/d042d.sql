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
taxonomy_demand AS (
    WITH taxonomy_unified AS (
        SELECT *,
            CASE
                WHEN first_update_source = 'SelfServiceWeb' THEN 'TENANT_PWA'
                WHEN first_update_source = 'Admin' THEN 'MAGIC_LINK'
                WHEN first_update_source = 'Sistema' THEN 'SYSTEM'
                WHEN first_update_source = 'Corretores' THEN 'AGENT_PWA'
                WHEN first_update_source = 'Inquilinos' THEN 'TENANT_NATIVE'
                WHEN first_update_source = 'Proprietarios' THEN 'OWNER_PWA'
                WHEN first_update_source = 'Portfolio' THEN 'PORTFOLIO_MANAGER'
                WHEN first_update_source = 'MagicLink' THEN 'MAGIC_LINK'
                WHEN first_update_source = 'WhatsApp' THEN 'WHATSAPP'
                ELSE UPPER(first_update_source)
            END AS first_update_source_unified
        FROM datalake_gsheets_clean.taxonomy_demand
    ),
    taxonomy_min_ids AS (
        SELECT
            MIN(CAST(id AS BIGINT)) AS id
        FROM
            taxonomy_unified
        GROUP BY
            LOWER(app_type),
            LOWER(utm_source),
            LOWER(utm_medium),
            LOWER(branded),
            LOWER(first_update_source_unified),
            flg_via_reschedule
    )
    SELECT
        CAST(td.id AS BIGINT) AS id,
        td.app_type,
        td.utm_source,
        td.utm_medium,
        td.branded,
        td.first_update_source,
        td.first_update_source_unified,
        CAST(td.flg_via_reschedule AS BOOLEAN) AS flg_via_reschedule,
        td.category AS mkt_category,
        td.flow AS mkt_flow,
        td.completion AS mkt_completion,
        td.channel AS mkt_channel,
        td.medium AS mkt_medium,
        td.origin AS mkt_origin,
        td.source AS mkt_source,
        td.platform AS mkt_platform
    FROM
        taxonomy_unified AS td
    JOIN
        taxonomy_min_ids AS td_min
            ON td.id = td_min.id
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
		CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_medium END AS mkt_medium,
    	CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_source END AS mkt_source,
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
	LEFT JOIN
		taxonomy_demand AS td
			ON LOWER(COALESCE(td.app_type, '')) = LOWER(COALESCE(IF(acc.visit_code IS NOT NULL, acc.final_attribution_app_type, src.app_type), ''))
			AND LOWER(COALESCE(td.utm_source, '')) = LOWER(COALESCE(IF(acc.visit_code IS NOT NULL, acc.final_attribution_source, src.utm_source), ''))
			AND LOWER(COALESCE(td.utm_medium, '')) = LOWER(COALESCE(IF(acc.visit_code IS NOT NULL, acc.final_attribution_medium, src.utm_medium), ''))
			AND LOWER(COALESCE(td.branded, '')) = LOWER(COALESCE(IF(acc.visit_code IS NOT NULL, COALESCE(acc.final_attribution_branded, "Outro"), COALESCE(src.branded, "Outro")),''))
			AND LOWER(COALESCE(td.first_update_source_unified, '')) = LOWER(COALESCE(v.visit_request_channel, ''))
			AND COALESCE(td.flg_via_reschedule, FALSE) = COALESCE(v.is_reschedule, FALSE)
	WHERE
		v.business_context = 'RENT'
    UNION ALL
	SELECT
		lrf.sk_client,
		lrf.sk_region,
		dof.mkt_medium,
		dof.mkt_source,
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
		tta.mkt_medium,
		tta.mkt_source,
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
		AND tp.mkt_medium = 'App Campaign'
		AND tp.mkt_source = 'Facebook'
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
		AND tp.mkt_medium = 'App Campaign'
		AND tp.mkt_source = 'Facebook'
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
