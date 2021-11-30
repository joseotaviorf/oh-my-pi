WITH
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
    dim_booking AS b
    JOIN fact_listing_rent_flows AS flrf
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
    dim_offer AS o
    JOIN fact_listing_rent_flows AS flrf
      ON o.sk_offer = flrf.sk_offer
  WHERE
    o.sk_offer > 0
    AND o.dt_first_sent IS NOT NULL
  UNION ALL
  SELECT
    tta.tenant_id::INT AS sk_client,
    fhl.sk_region,
    tta.mkt_medium,
    tta.mkt_source,
    tta.first_message_ts::TIMESTAMP AS ts_event
  FROM
    datamarts.talk_to_agent AS tta
    JOIN fact_house_listings AS fhl
      ON tta.sk_house_listing = fhl.sk_house_listing
  WHERE
    tta.business_context = 'RENT'
    AND tta.first_message_ts IS NOT NULL
),
--------------------------------------------------------------------------
-- Creating a list for dates and cities (Brasília, Salvador and Recife) --
--------------------------------------------------------------------------
date_region AS (
  SELECT
    DATE(evt.ts_event) as date,
    dr.city_group   
  FROM 
    tenant_prospect_events AS evt
  JOIN 
    dim_region AS dr 
    USING(sk_region)
  WHERE 
    dr.city_group IN ('Brasília', 'Recife', 'Salvador')   
  GROUP BY 1, 2
),
------------------------------------------------------------------------------
-- Order Tenant Prospects events by timestamp to extract only the first one --
------------------------------------------------------------------------------
tenant_prospects AS (
  SELECT
    evt.sk_client,
    evt.ts_event,
    dr.city_group,
    evt.mkt_medium,
    evt.mkt_source,
    DATE(evt.ts_event) AS date,
    ROW_NUMBER() OVER(PARTITION BY evt.sk_client
                      ORDER BY evt.ts_event) AS interactions_order
  FROM
    tenant_prospect_events AS evt
  JOIN 
    dim_region AS dr 
    USING(sk_region)
  WHERE
    mkt_medium = 'Display'
    AND mkt_source = 'Facebook'
)
SELECT
  dr.date as sk_date,
  dr.city_group,
  CASE 
    WHEN SUM(COUNT(DISTINCT CASE WHEN tp.interactions_order = 1 THEN tp.sk_client ELSE NULL END)) OVER(PARTITION BY dr.date)::FLOAT = 0 
      THEN 0.33 
    ELSE
      COUNT(DISTINCT CASE WHEN tp.interactions_order = 1 THEN tp.sk_client ELSE NULL END)
      / NULLIF(SUM(COUNT(DISTINCT CASE WHEN tp.interactions_order = 1 THEN tp.sk_client ELSE NULL END)) OVER(PARTITION BY dr.date)::FLOAT, 0)
  END AS share
FROM
  tenant_prospects AS tp
FULL OUTER JOIN 
  date_region AS dr
  ON 
  tp.date = dr.date 
  AND dr.city_group = tp.city_group
GROUP BY
	1,2