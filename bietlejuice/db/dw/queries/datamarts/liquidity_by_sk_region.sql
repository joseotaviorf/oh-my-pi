WITH
days_published AS (
  WITH
  published AS (
    SELECT
      sk_house AS sk_house_listing,
      SUBSTRING(sk_house, 1, 9) AS sk_house,
      DATE(sk_min_status_date) AS min_status_date,
      COALESCE(DATE(sk_max_status_date), CURRENT_DATE) AS max_status_date
    FROM fact_house_status
    WHERE status_history = 'publicado'
  ),
  rows AS (
    SELECT
      *,
      ROW_NUMBER() OVER(PARTITION BY sk_house, max_status_date ORDER BY max_status_date ASC) AS row
    FROM published
  )
  -- HACK: fact_house_status has an issue where it can have two rows with a published status and null max_status_date
  -- while we don't fix that, here we will take only the first row
  SELECT
    sk_house_listing,
    DATE_DIFF('day', min_status_date, max_status_date) AS days_published
  FROM rows WHERE row = 1
),
rent_flows_contracts AS (
  SELECT
    *
  FROM public.fact_listing_rent_flows
  WHERE days_house_listing_to_contract_signed IS NOT NULL
),
regions AS (
  SELECT
    DISTINCT rf.sk_house_listing, rf.sk_region
  FROM public.fact_listing_rent_flows rf
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
    dr.city_group,
    dp.days_published
  FROM public.dim_house_listing hl
  LEFT JOIN rent_flows_contracts rf ON hl.sk_house_listing = rf.sk_house_listing
  LEFT JOIN regions r ON hl.sk_house_listing = r.sk_house_listing
  LEFT JOIN public.dim_region dr ON r.sk_region = dr.sk_region
  LEFT JOIN days_published dp ON hl.sk_house_listing = dp.sk_house_listing
  WHERE r.sk_region IS NOT NULL AND r.sk_region != -1
),
liquidity_metrics AS (
  SELECT
    m.city_group,
    m.region_code,
    m.sk_region,
    m.house_bedrooms_category,
    SUM(CASE WHEN m.days_house_listing_to_contract_signed BETWEEN 0 AND 42 THEN 1 ELSE 0 END) AS rented_6_weeks,
    SUM(CASE WHEN m.days_house_listing_to_contract_signed NOT BETWEEN 0 AND 42 AND m.days_published >= 42 THEN 1 ELSE 0 END) AS not_rented_6_weeks,
    rented_6_weeks + not_rented_6_weeks AS sample_size,
    -- percent_rented_6_weeks
    rented_6_weeks / NULLIF(sample_size, 0)::REAL AS percent_rented_6_weeks,
    SQRT((1.96^2 * percent_rented_6_weeks * (1 - percent_rented_6_weeks)) / sample_size) AS percent_rented_6_weeks_error,
    percent_rented_6_weeks_error / NULLIF(percent_rented_6_weeks, 0) AS percent_rented_6_weeks_error_percent,
    CASE
      WHEN percent_rented_6_weeks_error <= 0.05 THEN 'low'
      WHEN percent_rented_6_weeks_error <= 0.10 THEN 'medium'
      WHEN percent_rented_6_weeks_error <= 0.20 THEN 'high'
      WHEN percent_rented_6_weeks_error > 0.20 THEN 'very high'
    END AS percent_rented_6_weeks_error_level,
    -- average_days_house_listing_to_contract_signed
    AVG(days_house_listing_to_contract_signed) AS average_days_house_listing_to_contract_signed,
    SQRT((1.96^2 * var_samp(days_house_listing_to_contract_signed)) / sample_size) AS average_days_house_listing_to_contract_signed_error,
    average_days_house_listing_to_contract_signed_error / NULLIF(average_days_house_listing_to_contract_signed, 0) AS average_days_house_listing_to_contract_signed_error_percent,
    MEDIAN(days_house_listing_to_contract_signed) AS median_days_house_listing_to_contract_signed
  FROM listings_metrics m
  GROUP BY 1, 2, 3, 4
  HAVING
    sample_size > 0
    AND percent_rented_6_weeks < 1
    AND percent_rented_6_weeks > 0
    AND percent_rented_6_weeks_error_level != 'very high'
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
  l.sample_size AS rentals_sample_size,
  -- percent_rented_6_weeks
  ROUND(percent_rented_6_weeks, 2) AS percent_rented_6_weeks,
  TO_CHAR((percent_rented_6_weeks - percent_rented_6_weeks_error), '0.00') || '-' || TO_CHAR((percent_rented_6_weeks + percent_rented_6_weeks_error), '0.00') AS percent_rented_6_weeks_interval,
  ROUND(percent_rented_6_weeks_error, 2) AS percent_rented_6_weeks_error,
  percent_rented_6_weeks_error_level,
  -- average_days_house_listing_to_contract_signed
  ROUND(average_days_house_listing_to_contract_signed) AS average_days_house_listing_to_contract_signed,
  ROUND((average_days_house_listing_to_contract_signed - average_days_house_listing_to_contract_signed_error), 0)::VARCHAR || '-' || ROUND((average_days_house_listing_to_contract_signed + average_days_house_listing_to_contract_signed_error), 0)::VARCHAR AS average_days_house_listing_to_contract_signed_interval,
  ROUND(average_days_house_listing_to_contract_signed_error, 2) AS average_days_house_listing_to_contract_signed_error,
  median_days_house_listing_to_contract_signed AS median_days_house_listing_to_contract_signed
FROM all_regions r
LEFT JOIN liquidity_metrics l ON r.city_group = l.city_group AND r.sk_region = l.sk_region AND r.house_bedrooms_category = l.house_bedrooms_category
WHERE
  r.house_bedrooms_category IS NOT NULL
ORDER BY
  r.city_group,
  r.region_code,
  r.sk_region,
  r.house_bedrooms_category
