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
    flrf.sk_client,
    flrf.sk_region,
    CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_medium END AS mkt_medium,
    CASE WHEN td.id IS NULL THEN 'Not Mapped' ELSE td.mkt_source END AS mkt_source,
    v.ts_created AS ts_event
  FROM
    datalake_visit.visits AS v
  JOIN
    rent_flow_client_info AS flrf
      ON v.id_visit = flrf.sk_visit
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
    flrf.sk_client,
    flrf.sk_region,
    o.mkt_medium,
    o.mkt_source,
    o.dt_first_sent AS ts_event
  FROM
    dw_rent.dim_offer AS o
    JOIN rent_flow_client_info AS flrf
      ON o.sk_offer = flrf.sk_offer
  WHERE
    o.sk_offer > 0
    AND o.dt_first_sent IS NOT NULL
  UNION ALL
  SELECT
    tta.tenant_id AS sk_client,
    fhl.sk_region,
    tta.mkt_medium,
    tta.mkt_source,
    tta.first_message_ts AS ts_event
  FROM
    datalake_talk_to_agent.talk_to_agent AS tta
    JOIN dw_rent.fact_house_listings AS fhl
      ON tta.sk_house_listing = fhl.sk_house_listing
  WHERE
    tta.business_context = 'RENT'
    AND tta.first_message_ts IS NOT NULL
),
------------------------------------------------------------------------------
-- Order Tenant Prospects events by timestamp to extract only the first one --
------------------------------------------------------------------------------
tenant_prospects AS (
  SELECT
    evt.sk_client,
    CAST(date_format(ts_event, 'yyyyMMdd') AS INT) as sk_date,
    dr.city_group,
    evt.mkt_medium,
    evt.mkt_source,
    ROW_NUMBER() OVER(PARTITION BY evt.sk_client
                      ORDER BY evt.ts_event) AS interactions_order
  FROM
    tenant_prospect_events AS evt
  JOIN
    dw_public.dim_region AS dr
    USING(sk_region)
),
grouped_tenant_prospects AS (
    SELECT
        sk_date,
        city_group,
        COUNT(CASE WHEN interactions_order = 1 THEN sk_client ELSE NULL END) AS nTP
    FROM tenant_prospects
    WHERE mkt_medium = 'Display'
        AND mkt_source = 'Facebook'
        AND city_group IN ('Brasília', 'Recife', 'Salvador')
    GROUP BY 1,2
),
date_region AS (
    SELECT
        CAST(date_format(evt.ts_event, 'yyyyMMdd') AS INT) as sk_date,
        dr.city_group
    FROM
        tenant_prospect_events AS evt
    JOIN
        dw_public.dim_region AS dr
        USING(sk_region)
    WHERE
        dr.city_group IN ('Brasília', 'Recife', 'Salvador')
    GROUP BY 1, 2
)
SELECT
  dr.sk_date AS id_date,
  '{id_rule}' AS id_rule,
  dr.city_group,
  CASE
    WHEN SUM(COALESCE(tp.nTP, 0)) OVER(PARTITION BY dr.sk_date) = 0
      THEN 0.33
    ELSE
      COALESCE(tp.nTP, 0)
        / NULLIF(SUM(COALESCE(tp.nTP, 0)) OVER(PARTITION BY dr.sk_date), 0)
  END AS share,
  'demand' AS funnel_side,
  CAST(NULL AS STRING) AS business_context
FROM
grouped_tenant_prospects AS tp
FULL OUTER JOIN date_region AS dr
	ON tp.sk_date = dr.sk_date AND dr.city_group = tp.city_group
