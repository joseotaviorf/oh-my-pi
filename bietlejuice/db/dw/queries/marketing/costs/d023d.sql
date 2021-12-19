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
------------------------------------------------------------------------------
-- Order Tenant Prospects events by timestamp to extract only the first one --
------------------------------------------------------------------------------
tenant_prospects AS (
  SELECT
    evt.sk_client,
    TO_CHAR(ts_event, 'YYYYMMDD')::INTEGER as sk_date,
    dr.city_group,
    evt.mkt_medium,
    evt.mkt_source,
    ROW_NUMBER() OVER(PARTITION BY evt.sk_client
                      ORDER BY evt.ts_event) AS interactions_order
  FROM
    tenant_prospect_events AS evt
  JOIN
    dim_region AS dr
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
        TO_CHAR(evt.ts_event, 'YYYYMMDD')::INTEGER as sk_date,
        dr.city_group
    FROM
        tenant_prospect_events AS evt
    JOIN
        dim_region AS dr
        USING(sk_region)
    WHERE
        dr.city_group IN ('Brasília', 'Recife', 'Salvador')
    GROUP BY 1, 2
)
SELECT
  dr.sk_date,
  dr.city_group,
  CASE
        WHEN SUM(COALESCE(tp.nTP, 0)) OVER(PARTITION BY dr.sk_date)::FLOAT = 0
            THEN 0.33
        ELSE
            COALESCE(tp.nTP, 0)
                / NULLIF(SUM(COALESCE(tp.nTP, 0)) OVER(PARTITION BY dr.sk_date)::FLOAT, 0)
   END AS share
FROM
  grouped_tenant_prospects AS tp
  FULL OUTER JOIN date_region AS dr
    ON tp.sk_date = dr.sk_date AND dr.city_group = tp.city_group