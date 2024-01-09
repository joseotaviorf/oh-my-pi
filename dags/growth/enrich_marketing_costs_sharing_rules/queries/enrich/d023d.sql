WITH
-----------------------------------------------------------
----- CTE to fetch information from listing rent flow -----
-----------------------------------------------------------
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
        dw_rent.dim_offer
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
    flrf.sk_client,
    flrf.sk_region,
    b.mkt_medium,
    b.mkt_source,
    b.dt_created AS ts_event
  FROM
    dw_public.dim_booking AS b
    JOIN rent_flow_client_info AS flrf
      on b.sk_booking = flrf.sk_booking
  WHERE
    b.sk_booking > 0
    AND b.visit_intent = 'RENT'
    AND b.type = 'Visita'
    AND b.dt_created IS NOT NULL
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
    JOIN dw_public.fact_house_listings AS fhl
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
