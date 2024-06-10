WITH 
contracts AS (
  SELECT
    fhl.sk_house_listing,
    CASE 
      WHEN 
        dhl.rent <= 1500 THEN 'LOW'
      WHEN 
        dhl.rent < 2500 THEN 'MEDIUM'
      WHEN 
        dhl.rent >= 2500 THEN 'HIGH'
      ELSE 
        'UNDEFINED'
    END AS value_segment,
    COALESCE(fhl.sk_contract, fhl.sk_previous_contract) AS id_contract_listing
  FROM
    dw_rent.fact_house_listings AS fhl
  JOIN
    dw_rent.dim_house_listing AS dhl
      ON dhl.sk_house_listing = fhl.sk_house_listing
),
base_contract AS (
  SELECT
    c.sk_house_listing,
    c.id_contract_listing,
    COALESCE(dc.value_segment, c.value_segment) AS category
  FROM
    contracts AS c
  LEFT JOIN
    dw_rent.dim_contract AS dc
      ON dc.sk_contract = c.id_contract_listing
),
aux_rf AS (
  SELECT DISTINCT
    sk_rent_flow,
    dd.date AS rf_date
  FROM 
    dw_rent.fact_rent_flows AS rf
  JOIN 
    dw_public.dim_date AS dd
      ON rf.sk_first_event_date = dd.sk_date
),
base_rent_flows AS (
  SELECT
    DATE_TRUNC('MONTH', rf_date) AS dt_month_start,
    dhl.listing_category_start,
    dr.country_code,
    bc.category,
    COUNT(DISTINCT frf.sk_rent_flow) AS rent_flows
  FROM 
    dw_rent.fact_listing_rent_flows AS frf
  LEFT JOIN 
    aux_rf AS a
      ON frf.sk_rent_flow = a.sk_rent_flow
  LEFT JOIN
    dw_rent.dim_house_listing AS dhl
      ON frf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON frf.sk_region = dr.sk_region
  JOIN 
    base_contract AS bc
      ON bc.sk_house_listing = frf.sk_house_listing
  WHERE 
    dhl.listing_category_start IN ('First Listing','Re-Listing')
  GROUP BY 
    1, 2, 3, 4
),
published_listings AS (
  SELECT
    dd.month_start AS dt_month_start,
    fhldi.country_code,
    listing_category_start,
    bc.category,
    COUNT(DISTINCT fhldi.sk_house_listing) AS listings
  FROM 
    dw_rent.dim_house_listing AS dhl
  LEFT JOIN 
    dw_rent.fact_house_listing_daily_infos AS fhldi
      ON dhl.sk_house_listing = fhldi.sk_house_listing
  LEFT JOIN 
    dw_public.dim_date AS dd
      ON fhldi.sk_date = dd.sk_date
  LEFT JOIN 
    dw_rent.dim_house_status AS dhs
      ON fhldi.sk_house_status = dhs.sk_house_status
  JOIN 
    base_contract AS bc
      ON bc.sk_house_listing = dhl.sk_house_listing
  WHERE 
    dhl.listing_category_start IN ('Re-Listing', 'First Listing')
    AND dhl.ts_publication IS NOT NULL
    AND dhs.house_status = 'PUBLISHED'
  GROUP BY 
    1, 2, 3, 4
), 
comp AS (
  SELECT
    pl.dt_month_start,
    pl.country_code,
    pl.category,
    pl.listing_category_start AS cat,
    pl.listings,
    brf.rent_flows
  FROM 
    published_listings AS pl
  LEFT JOIN 
    base_rent_flows AS brf 
      ON pl.dt_month_start = brf.dt_month_start 
        AND pl.country_code = brf.country_code
        AND pl.category = brf.category
        AND pl.listing_category_start = brf.listing_category_start
),
metric_calculations AS (
  SELECT 
    dt_month_start,
    country_code,
    category,
    SUM(IF(cat='First Listing', listings, 0)) AS published_first_listings,
    SUM(IF(cat='First Listing', rent_flows, 0)) AS first_listings_total_rent_flows,
    SUM(IF(cat='First Listing', rent_flows, 0))*1.00/SUM(IF(cat='First Listing', listings, 0)) AS first_listings_ratio,
    SUM(IF(cat='Re-Listing', listings, 0)) AS published_relistings,
    SUM(IF(cat='Re-Listing', rent_flows, 0)) AS relistings_total_rent_flows,
    SUM(IF(cat='Re-Listing', rent_flows, 0))*1.00/SUM(IF(cat='Re-Listing', listings, 0)) AS relistings_ratio
  FROM 
    comp
  GROUP BY 
    1, 2, 3
  
  UNION ALL

  SELECT 
    dt_month_start,
    country_code,
    'OVERALL' AS category,
    SUM(IF(cat='First Listing', listings, 0)) AS published_first_listings,
    SUM(IF(cat='First Listing', rent_flows, 0)) AS first_listings_total_rent_flows,
    SUM(IF(cat='First Listing', rent_flows, 0))*1.00/SUM(IF(cat='First Listing', listings, 0)) AS first_listings_ratio,
    SUM(IF(cat='Re-Listing', listings, 0)) AS published_relistings,
    SUM(IF(cat='Re-Listing', rent_flows, 0)) AS relistings_total_rent_flows,
    SUM(IF(cat='Re-Listing', rent_flows, 0))*1.00/SUM(IF(cat='Re-Listing', listings, 0)) AS relistings_ratio
  FROM 
    comp
  GROUP BY 
    1, 2, 3

)
SELECT
  dt_month_start,
  category,
  country_code,
  published_first_listings,
  first_listings_total_rent_flows,
  first_listings_ratio,
  published_relistings,
  relistings_total_rent_flows,
  relistings_ratio,
  relistings_ratio * 1.00/first_listings_ratio AS rent_flows_per_listing_rl_vs_fl_ratio
FROM 
  metric_calculations