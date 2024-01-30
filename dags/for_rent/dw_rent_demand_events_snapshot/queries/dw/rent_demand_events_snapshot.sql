SELECT
  DATE_FORMAT(CURRENT_DATE, 'yyyyMMdd') AS id_snapshot,
  CASE
    WHEN MONTH(TO_DATE(CAST(sk_event_date AS STRING), 'yyyyMMdd')) <= 6 THEN 1
    ELSE 2
  END AS halfyear,
  EXTRACT(quarter FROM dt.date) AS quarter,
  dr.city_group,
  dr.tier,
  CASE
    WHEN dhl.is_b2b = TRUE THEN 'B2B'
    WHEN dhl.first_consultant_type = 'CIQ_MANAGER' THEN 'ASP'
    WHEN dhl.is_for_rent = TRUE AND (dhl.first_consultant_type IS NOT NULL AND dhl.first_consultant_type <> 'Core') THEN dhl.first_consultant_type
    WHEN dhl.is_b2b = FALSE OR (dhl.first_consultant_type IS NULL OR dhl.first_consultant_type = 'Core') THEN 'CORE'
  END AS business_type,
  dhl.listing_category_start,
  CASE
    WHEN drf.first_touchpoint = 'DIRECT' THEN drf.first_touchpoint
    ELSE 'VISIT'
  END AS rent_flow_origin,
  dhl.rental_administrator,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 1) AS visits_booked,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 2) AS visits_completed,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 3) AS offers_submitted,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 4) AS offers_accepted,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 5) AS evaluation_started,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 6) AS evaluation_positive,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 7) AS documentation_sent,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 8) AS credit_approved,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 9) AS contracts_signed,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 10) AS contracts_created,
  CASE
    WHEN fde.sk_event_type BETWEEN 1 AND 4 THEN FALSE
    WHEN fde.sk_event_type > 4 AND dp.guarantee = 'RentalGuarantee' THEN TRUE
    ELSE FALSE
  END AS has_guarantee,
  TO_DATE(dt.date, 'yyyy-mm-dd') AS dt_event,
  TO_DATE(DATE_TRUNC('week', dt.date), 'yyyy-mm-dd') AS dt_week_started,
  NOW() AS ts_snapshot,
  fde.country_code,
  YEAR(fde.ts_load) AS year,
  MONTH(fde.ts_load) AS month,
  DAY(fde.ts_load) AS day
FROM
  dw_rent.fact_rent_demand_events AS fde
JOIN
  dw_public.dim_date AS dt -- event date
    ON (dt.sk_date = fde.sk_event_date)
LEFT JOIN
  dw_public.dim_region AS dr -- city_groups
    ON (dr.sk_region = fde.sk_region)
LEFT JOIN
  dw_rent.dim_house_listing AS dhl -- listings info
    ON fde.sk_house_listing = dhl.sk_house_listing
LEFT JOIN
  dw_rent.fact_rent_flows AS frf
    ON fde.sk_rent_flow = frf.sk_rent_flow
LEFT JOIN
  dw_rent.dim_rent_flow_type AS drf
    ON frf.sk_rent_flow_type = drf.sk_rent_flow_type
LEFT JOIN
  dw_rent.dim_proposal AS dp -- guarantee
    ON fde.sk_proposal = dp.sk_proposal
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 20, 21, 22, 23, 24, 25, 26, 27
