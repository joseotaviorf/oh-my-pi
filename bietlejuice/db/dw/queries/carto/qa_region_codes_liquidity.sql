WITH
periods_published AS (
  SELECT
    sk_house AS sk_house_listing,
    DATE(sk_max_status_date) AS sk_max_status_date,
    DATE(sk_min_status_date) AS sk_min_status_date
  FROM public.fact_house_status
  WHERE status_history = 'publicado'
    AND sk_max_status_date IS NOT NULL
  UNION ALL
  SELECT
    sk_house AS sk_house_listing,
    CURRENT_DATE AS sk_max_status_date,
    DATE(sk_min_status_date) AS sk_min_status_date
  FROM public.fact_house_status
  WHERE status_history = 'publicado'
    AND sk_max_status_date IS NULL
),
days_published AS (
  SELECT
    sk_house_listing,
    SUM(DATE_DIFF('day', sk_min_status_date, sk_max_status_date)) AS days_published
  FROM periods_published
  GROUP BY 1
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
    hl.rent,
    hl.house_condo,
    hl.house_total_value,
    hl.house_total_area,
    hl.house_total_value / NULLIF(hl.house_total_area, 0) AS house_total_value_per_square_meter,
    hl.rent / NULLIF(hl.house_total_area, 0) AS rent_per_square_meter,
    c.rent AS contract_rent,
    c.status AS contract_status,
    c.condo AS contract_condo,
    c.iptu AS contract_iptu,
    (c.rent + c.condo) AS contract_total_value,
    contract_total_value / NULLIF(hl.house_total_area, 0) AS contract_total_value_per_square_meter,
    c.rent / NULLIF(hl.house_total_area, 0) AS contract_rent_per_square_meter,
    hl.house_bedrooms,
    CASE
      WHEN hl.house_bedrooms IN (1, 2) THEN '1-2'
      WHEN hl.house_bedrooms = 3 THEN '3'
      WHEN hl.house_bedrooms > 3 THEN '4+'
      ELSE NULL
    END AS house_bedrooms_category,
    hl.house_bathrooms,
    hl.house_type,
    hl.house_predicted_price,
    hl.status,
    hl.house_status,
    rf.days_visit_to_offer_submitted,
    rf.days_house_listing_to_contract_signed,
    dr.sk_region,
    dr.name AS region_name,
    dr.region_code,
    dr.city_name,
    dr.city_group,
    dp.days_published
  FROM public.dim_house_listing hl
  LEFT JOIN rent_flows_contracts rf ON hl.sk_house_listing = rf.sk_house_listing
  LEFT JOIN regions r ON hl.sk_house_listing = r.sk_house_listing
  LEFT JOIN public.dim_region dr ON r.sk_region = dr.sk_region
  LEFT JOIN days_published dp ON hl.sk_house_listing = dp.sk_house_listing
  LEFT JOIN dim_contract c ON rf.sk_contract = c.sk_contract
  WHERE r.sk_region IS NOT NULL AND r.sk_region != -1
),
liquidity_metrics AS (
  SELECT
    m.city_group,
    m.region_code,
    m.house_bedrooms_category,
    SUM(CASE WHEN m.days_house_listing_to_contract_signed BETWEEN 0 AND 42 THEN 1 ELSE 0 END) AS rented_6_weeks,
    SUM(CASE WHEN m.days_house_listing_to_contract_signed NOT BETWEEN 0 AND 42 AND m.days_published >= 42 THEN 1 ELSE 0 END) AS not_rented_6_weeks,
    rented_6_weeks + not_rented_6_weeks AS sample_size,

    rented_6_weeks / NULLIF(sample_size, 0)::REAL AS percent_rented_6_weeks,
    SQRT((1.96^2 * percent_rented_6_weeks * (1 - percent_rented_6_weeks)) / sample_size) AS percent_rented_6_weeks_error,
    percent_rented_6_weeks_error / NULLIF(percent_rented_6_weeks, 0) AS percent_rented_6_weeks_error_percent,

    AVG(days_house_listing_to_contract_signed) AS average_days_house_listing_to_contract_signed,
    SQRT((1.96^2 * var_samp(days_house_listing_to_contract_signed)) / sample_size) AS average_days_house_listing_to_contract_signed_error,
    average_days_house_listing_to_contract_signed_error / NULLIF(average_days_house_listing_to_contract_signed, 0) AS average_days_house_listing_to_contract_signed_error_percent,

    MEDIAN(days_house_listing_to_contract_signed) AS median_days_house_listing_to_contract_signed
  FROM listings_metrics m
  -- WHERE
  --   m.days_house_listing_to_contract_signed BETWEEN 0 AND 42
  --   OR (m.days_house_listing_to_contract_signed NOT BETWEEN 0 AND 42 AND m.days_published >= 42)
  GROUP BY 1, 2, 3
  HAVING
    sample_size > 0
    AND percent_rented_6_weeks < 1
),
pricing_metrics AS (
  SELECT
    m.city_group,
    m.region_code,
    m.house_bedrooms_category,
    COUNT(*) as sample_size,

    AVG(rent) AS average_asked_rent,
    SQRT((1.96^2 * var_samp(rent)) / sample_size) AS average_asked_rent_error,
    average_asked_rent_error / NULLIF(average_asked_rent, 0) AS average_asked_rent_error_percent,

    -- AVG(house_condo) AS average_condo,
    -- SQRT((1.96^2 * var_samp(house_condo)) / sample_size) AS average_condo_error,
    -- average_condo_error / NULLIF(average_condo, 0) AS average_condo_error_percent,

    AVG(house_total_value) AS average_asked_total_value,
    SQRT((1.96^2 * var_samp(house_total_value)) / sample_size) AS average_asked_total_value_error,
    average_asked_total_value_error / NULLIF(average_asked_total_value, 0) AS average_asked_total_value_error_percent,

    AVG(house_total_value_per_square_meter) AS average_asked_total_value_per_square_meter,
    SQRT((1.96^2 * var_samp(house_total_value_per_square_meter)) / sample_size) AS average_asked_total_value_per_square_meter_error,
    average_asked_total_value_per_square_meter_error / NULLIF(average_asked_total_value_per_square_meter, 0) AS average_asked_total_value_per_square_meter_error_percent,

    AVG(rent_per_square_meter) AS average_asked_rent_per_square_meter,
    SQRT((1.96^2 * var_samp(rent_per_square_meter)) / sample_size) AS average_asked_rent_per_square_meter_error,
    average_asked_rent_per_square_meter_error / NULLIF(average_asked_rent_per_square_meter, 0) AS average_asked_rent_per_square_meter_error_percent,

    AVG(contract_rent) AS average_contract_rent,
    SQRT((1.96^2 * var_samp(contract_rent)) / sample_size) AS average_contract_rent_error,
    average_contract_rent_error / NULLIF(average_contract_rent, 0) AS average_contract_rent_error_percent,

    AVG(contract_condo) AS average_contract_condo,
    SQRT((1.96^2 * var_samp(contract_condo)) / sample_size) AS average_contract_condo_error,
    average_contract_condo_error / NULLIF(average_contract_condo, 0) AS average_contract_condo_error_percent,

    AVG(contract_total_value) AS average_contract_total_value,
    SQRT((1.96^2 * var_samp(contract_total_value)) / sample_size) AS average_contract_total_value_error,
    average_contract_total_value_error / NULLIF(average_contract_total_value, 0) AS average_contract_total_value_error_percent,

    AVG(contract_total_value_per_square_meter) AS average_contract_total_value_per_square_meter,
    SQRT((1.96^2 * var_samp(contract_total_value_per_square_meter)) / sample_size) AS average_contract_total_value_per_square_meter_error,
    average_contract_total_value_per_square_meter_error / NULLIF(average_contract_total_value_per_square_meter, 0) AS average_contract_total_value_per_square_meter_error_percent,

    AVG(contract_rent_per_square_meter) AS average_contract_rent_per_square_meter,
    SQRT((1.96^2 * var_samp(contract_rent_per_square_meter)) / sample_size) AS average_contract_rent_per_square_meter_error,
    average_contract_rent_per_square_meter_error / NULLIF(average_contract_rent_per_square_meter, 0) AS average_contract_rent_per_square_meter_error_percent
  FROM listings_metrics m
  WHERE
    m.days_house_listing_to_contract_signed BETWEEN 0 AND 42
    OR (m.days_house_listing_to_contract_signed NOT BETWEEN 0 AND 42 AND m.days_published >= 42)
  GROUP BY 1, 2, 3
  HAVING
    sample_size > 0
),
all_regions AS (
  SELECT
    DISTINCT city_group, region_code, house_bedrooms_category
  FROM public.dim_region
  CROSS JOIN (
    SELECT '1-2' AS house_bedrooms_category
    UNION ALL
    SELECT '3'
    UNION ALL
    SELECT '4+'
  ) AS categories
  WHERE
    sk_region != -1
    AND level = 'SubRegiao'
    AND city_group IS NOT NULL
    AND region_code IS NOT NULL
)
SELECT
  city_group,
  region_code,
  house_bedrooms_category,
  l.sample_size AS listings_sample_size,

  ROUND(percent_rented_6_weeks, 2) AS percent_rented_6_weeks,
  ROUND((percent_rented_6_weeks - percent_rented_6_weeks_error), 2)::VARCHAR || '-' || ROUND((percent_rented_6_weeks + percent_rented_6_weeks_error), 2)::VARCHAR AS percent_rented_6_weeks_interval,
  CASE
    WHEN percent_rented_8_weeks_error <= 0.05 THEN 'Low'
    WHEN percent_rented_8_weeks_error <= 0.10 THEN 'Medium'
    WHEN percent_rented_8_weeks_error >= 0.10 THEN 'High'
  END AS percent_rented_8_weeks_error_level,

  ROUND(average_days_house_listing_to_contract_signed) AS average_days_house_listing_to_contract_signed,
  ROUND((average_days_house_listing_to_contract_signed - average_days_house_listing_to_contract_signed_error), 0)::VARCHAR || '-' || ROUND((average_days_house_listing_to_contract_signed + average_days_house_listing_to_contract_signed_error), 0)::VARCHAR AS average_days_house_listing_to_contract_signed_interval,
  -- ROUND(average_days_house_listing_to_contract_signed_error_percent, 2) AS average_days_house_listing_to_contract_signed_error_percent,

  ROUND(average_asked_rent) AS average_asked_rent,
  ROUND((average_asked_rent - average_asked_rent_error), 0)::VARCHAR || '-' || ROUND((average_asked_rent + average_asked_rent_error), 0)::VARCHAR AS average_asked_rent_interval,
  -- ROUND(average_asked_rent_error_percent, 2) AS average_asked_rent_error_percent,

  ROUND(average_asked_total_value) AS average_asked_total_value,
  ROUND((average_asked_total_value - average_asked_total_value_error), 0)::VARCHAR || '-' || ROUND((average_asked_total_value + average_asked_total_value_error), 0)::VARCHAR AS average_asked_total_value_interval,
  -- ROUND(average_asked_total_value_error_percent, 2) AS average_asked_total_value_error_percent,

  ROUND(average_asked_total_value_per_square_meter) AS average_asked_total_value_per_square_meter,
  ROUND((average_asked_total_value_per_square_meter - average_asked_total_value_per_square_meter_error), 0)::VARCHAR || '-' || ROUND((average_asked_total_value_per_square_meter + average_asked_total_value_per_square_meter_error), 0)::VARCHAR AS average_asked_total_value_per_square_meter_interval,
  -- ROUND(average_asked_total_value_per_square_meter_error_percent, 2) AS average_asked_total_value_per_square_meter_error_percent,

  ROUND(average_asked_rent_per_square_meter) AS average_asked_rent_per_square_meter,
  ROUND((average_asked_rent_per_square_meter - average_asked_rent_per_square_meter_error), 0)::VARCHAR || '-' || ROUND((average_asked_rent_per_square_meter + average_asked_rent_per_square_meter_error), 0)::VARCHAR AS average_asked_rent_per_square_meter_interval,
  -- ROUND(average_asked_rent_per_square_meter_error_percent, 2) AS average_asked_rent_per_square_meter_error_percent,

  ROUND(average_contract_rent) AS average_contract_rent,
  ROUND((average_contract_rent - average_contract_rent_error), 0)::VARCHAR || '-' || ROUND((average_contract_rent + average_contract_rent_error), 0)::VARCHAR AS average_contract_rent_interval,
  -- ROUND(average_contract_rent_error_percent, 2) AS average_contract_rent_error_percent,

  ROUND(average_contract_condo) AS average_contract_condo,
  ROUND((average_contract_condo - average_contract_condo_error), 0)::VARCHAR || '-' || ROUND((average_contract_condo + average_contract_condo_error), 0)::VARCHAR AS average_contract_condo_interval,
  -- ROUND(average_contract_condo_error_percent, 2) AS average_contract_condo_error_percent,

  ROUND(average_contract_total_value) AS average_contract_total_value,
  ROUND((average_contract_total_value - average_contract_total_value_error), 0)::VARCHAR || '-' || ROUND((average_contract_total_value + average_contract_total_value_error), 0)::VARCHAR AS average_contract_total_value_interval,
  -- ROUND(average_contract_total_value_error_percent, 2) AS average_contract_total_value_error_percent,

  ROUND(average_contract_total_value_per_square_meter) AS average_contract_total_value_per_square_meter,
  ROUND((average_contract_total_value_per_square_meter - average_contract_total_value_per_square_meter_error), 0)::VARCHAR || '-' || ROUND((average_contract_total_value_per_square_meter + average_contract_total_value_per_square_meter_error), 0)::VARCHAR AS average_contract_total_value_per_square_meter_interval,
  -- ROUND(average_contract_total_value_per_square_meter_error_percent, 2) AS average_contract_total_value_per_square_meter_error_percent,

  ROUND(average_contract_rent_per_square_meter) AS average_contract_rent_per_square_meter,
  ROUND((average_contract_rent_per_square_meter - average_contract_rent_per_square_meter_error), 0)::VARCHAR || '-' || ROUND((average_contract_rent_per_square_meter + average_contract_rent_per_square_meter_error), 0)::VARCHAR AS average_contract_rent_per_square_meter_interval
  -- ,
  -- ROUND(average_contract_rent_per_square_meter_error_percent, 2) AS average_contract_rent_per_square_meter_error_percent

FROM all_regions r
FULL OUTER JOIN liquidity_metrics l USING(city_group, region_code, house_bedrooms_category)
FULL OUTER JOIN pricing_metrics p USING(city_group, region_code, house_bedrooms_category)
WHERE
  house_bedrooms_category IS NOT NULL
ORDER BY
  city_group,
  house_bedrooms_category,
  percent_rented_6_weeks DESC


-- TODO: add crawled listings metrics
