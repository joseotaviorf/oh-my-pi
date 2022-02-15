WITH
rent_flows_contracts AS (
  SELECT
    DISTINCT sk_house_listing,
    MAX(days_house_listing_to_contract_signed) AS days_house_listing_to_contract_signed
  FROM public.fact_listing_rent_flows
  WHERE days_house_listing_to_contract_signed IS NOT NULL
  GROUP BY 1
),
listings_metrics AS (
  SELECT
    hl.sk_house_listing,
    hl.house_bedrooms,
    CASE
      WHEN hl.house_bedrooms IN (1, 2) THEN '1-2'
      WHEN hl.house_bedrooms = 3 THEN '3'
      WHEN hl.house_bedrooms > 3 THEN '4+'
      ELSE NULL
    END AS house_bedrooms_category,
    rf.days_house_listing_to_contract_signed,
    dr.name AS region_name,
    dr.sk_region,
    dr.region_code,
    dr.city_group
  FROM public.dim_house_listing hl
  LEFT JOIN fact_house_listings fhl ON hl.sk_house_listing = fhl.sk_house_listing
  LEFT JOIN rent_flows_contracts rf ON hl.sk_house_listing = rf.sk_house_listing
  LEFT JOIN public.dim_region dr ON fhl.sk_region = dr.sk_region
  WHERE dr.sk_region != -1
    AND hl.ts_publication IS NOT NULL
    AND hl.ts_publication >= CURRENT_DATE-365
),
liquidity_metrics AS (
  SELECT
    m.city_group,
    m.region_code,
    m.sk_region,
    m.house_bedrooms_category,
    SUM(CASE WHEN m.days_house_listing_to_contract_signed BETWEEN 0 AND 42 THEN 1 ELSE 0 END) AS rented_in_6_weeks,
    COUNT(*) AS sample_size,
    -- percent_rented_in_6_weeks
    rented_in_6_weeks / NULLIF(sample_size, 0)::REAL AS percent_rented_in_6_weeks,
    SQRT((1.96^2 * percent_rented_in_6_weeks * (1 - percent_rented_in_6_weeks)) / sample_size) AS percent_rented_in_6_weeks_error,
    percent_rented_in_6_weeks_error / NULLIF(percent_rented_in_6_weeks, 0) AS percent_rented_in_6_weeks_error_percent,
    CASE
      WHEN percent_rented_in_6_weeks_error <= 0.05 THEN 'low'
      WHEN percent_rented_in_6_weeks_error <= 0.10 THEN 'medium'
      WHEN percent_rented_in_6_weeks_error <= 0.20 THEN 'high'
      WHEN percent_rented_in_6_weeks_error > 0.20 THEN 'very high'
    END AS percent_rented_in_6_weeks_error_level,
    -- average_days_house_listing_to_contract_signed
    AVG(days_house_listing_to_contract_signed) AS average_days_house_listing_to_contract_signed,
    SQRT((1.96^2 * var_samp(days_house_listing_to_contract_signed)) / sample_size) AS average_days_house_listing_to_contract_signed_error,
    average_days_house_listing_to_contract_signed_error / NULLIF(average_days_house_listing_to_contract_signed, 0) AS average_days_house_listing_to_contract_signed_error_percent,
    MEDIAN(days_house_listing_to_contract_signed) AS median_days_house_listing_to_contract_signed
  FROM listings_metrics m
  GROUP BY 1, 2, 3, 4
  HAVING
    sample_size > 0
    AND percent_rented_in_6_weeks < 1
    AND percent_rented_in_6_weeks > 0
    AND percent_rented_in_6_weeks_error_level != 'very high'
),
all_regions AS (
  SELECT
    DISTINCT city_group, region_code, sk_region, house_bedrooms_category, min_bedrooms, max_bedrooms
  FROM public.dim_region
  CROSS JOIN (
    SELECT '1-2' AS house_bedrooms_category, 1 AS min_bedrooms, 2 AS max_bedrooms
    UNION ALL
    SELECT '3' AS house_bedrooms_category, 3 AS min_bedrooms, 3 AS max_bedrooms
    UNION ALL
    SELECT '4+' AS house_bedrooms_category, 4 AS min_bedrooms, 100 AS max_bedrooms
  ) AS categories
  WHERE
    sk_region != -1
    AND level = 'SubRegiao'
    AND city_group IS NOT NULL
    AND region_code IS NOT NULL
    AND sk_region IS NOT NULL
)
SELECT
  r.city_group,
  r.region_code,
  r.sk_region,
  r.house_bedrooms_category,
  r.min_bedrooms,
  r.max_bedrooms,
  l.sample_size AS listings_sample_size,
  l.rented_in_6_weeks,
  -- percent_rented_in_6_weeks
  ROUND(percent_rented_in_6_weeks, 2) AS percent_rented_in_6_weeks,
  TO_CHAR((percent_rented_in_6_weeks - percent_rented_in_6_weeks_error), '0.00') || '-' || TO_CHAR((percent_rented_in_6_weeks + percent_rented_in_6_weeks_error), '0.00') AS percent_rented_in_6_weeks_interval,
  ROUND(percent_rented_in_6_weeks_error, 2) AS percent_rented_in_6_weeks_error,
  percent_rented_in_6_weeks_error_level,
  -- average_days_house_listing_to_contract_signed
  ROUND(average_days_house_listing_to_contract_signed) AS average_days_house_listing_to_contract_signed,
  ROUND((average_days_house_listing_to_contract_signed - average_days_house_listing_to_contract_signed_error), 0)::VARCHAR || '-' || ROUND((average_days_house_listing_to_contract_signed + average_days_house_listing_to_contract_signed_error), 0)::VARCHAR AS average_days_house_listing_to_contract_signed_interval,
  ROUND(average_days_house_listing_to_contract_signed_error, 2) AS average_days_house_listing_to_contract_signed_error,
  median_days_house_listing_to_contract_signed AS median_days_house_listing_to_contract_signed,
  current_timestamp as ts_load
FROM all_regions r
LEFT JOIN liquidity_metrics l ON r.city_group = l.city_group AND r.sk_region = l.sk_region AND r.house_bedrooms_category = l.house_bedrooms_category
WHERE
  r.house_bedrooms_category IS NOT NULL
ORDER BY
  r.city_group,
  r.region_code,
  r.sk_region,
  r.house_bedrooms_category
