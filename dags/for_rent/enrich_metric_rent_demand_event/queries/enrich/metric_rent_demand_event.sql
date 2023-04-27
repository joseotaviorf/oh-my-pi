SELECT
  CASE 
    WHEN dhl.is_b2b = TRUE THEN 'B2B'
    WHEN dhl.first_consultant_type = 'CIQ_MANAGER' THEN 'ASP'
    WHEN dhl.is_for_rent = TRUE AND (dhl.first_consultant_type IS NOT NULL AND dhl.first_consultant_type <> 'Core') THEN dhl.first_consultant_type
    WHEN dhl.is_b2b = FALSE OR (dhl.first_consultant_type IS NULL OR dhl.first_consultant_type = 'Core') THEN 'CORE'
  END AS business_type,
  dr.city_group,
  dp.guarantee AS guarantee,
  CASE 
    WHEN fde.month <= 6 THEN 1
    ELSE 2
  END AS halfyear,
  dhl.listing_category_start,
  extract(quarter FROM dt.date) AS quarter,
  CASE 
    WHEN funnel_first_touchpoint = 'DIRECT' THEN funnel_first_touchpoint
    ELSE 'VISIT' 
  END AS rent_flow_origin,
  dhl.rental_administrator,
  dr.tier,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 1) AS visits_booked,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 2) AS visits_completed,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 3) AS offers_submitted,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 4) AS offers_accepted,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 5) AS evaluation_started,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 6) AS evaluation_positive,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 7) AS documentation_sent,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 8) AS credit_approved,
  COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 9) AS contracts_signed,
  TO_DATE(dt.date, 'yyyy-mm-dd') AS dt_event,  
  TO_DATE(date_trunc('week', dt.date), 'yyyy-mm-dd') AS dt_week_started,
  fde.year,
  fde.month,
  fde.day,
  fde.country_code,
  CURRENT_TIMESTAMP AS ts_updated
FROM 
  dw_rent.fact_rent_demand_events AS fde
JOIN 
  dw_public.dim_date AS dt --event date
    ON (dt.sk_date = fde.sk_event_date)
LEFT JOIN 
  dw_public.dim_region AS dr --city_groups
    ON (dr.sk_region = fde.sk_region)
LEFT JOIN 
  dw_public.dim_house_listing AS dhl --listings info
    ON fde.sk_house_listing = dhl.sk_house_listing 
LEFT JOIN 
  dw_datamarts.funnel_demand_flows AS fdf --first touchpoint
    ON fde.sk_rent_flow = fdf.sk_rent_flow        
    AND fde.sk_house_listing = fdf.sk_house_listing
LEFT JOIN 
  dw_public.dim_proposal AS dp --guarantee
    ON fde.sk_proposal = dp.sk_proposal
WHERE 
  fde.year = {year} 
  AND fde.month = {month} 
  AND fde.day = {day}
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 19, 20, 21, 22, 23, 24