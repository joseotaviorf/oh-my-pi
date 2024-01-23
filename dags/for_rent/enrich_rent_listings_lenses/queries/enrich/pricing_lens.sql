WITH historical_prices AS (
  SELECT 
    id_house,
    id_house_listing,
    id_region, 
    price,
    calculator_rent_price AS calculator_price,
    calculator_certainty,
    (price / calculator_rent_price) - 1 AS diff_calculator_price,
    ts_price_started
  FROM 
    datalake_ebdb_pricing.rent_listing_price_changes
),
actual_prices AS (
  SELECT
    h.id AS id_house,
    hl.id_house_listing,
    h.id_region, 
    h.rent AS price,
    p.p_50 AS calculator_price,
    p.certainty AS calculator_certainty,
    (h.rent / p.p_50) - 1. AS diff_calculator_price,
    CURRENT_TIMESTAMP() AS ts_price_started
  FROM
    datalake_ebdb_listing.house AS h
  LEFT JOIN 
    datalake_ebdb_listing.house_listing AS hl
      ON h.id = hl.id_house
  LEFT JOIN 
    datalake_ebdb_clean.house_predicted_price AS p
      ON h.id = p.id_house
      AND p.business_context = 'RENT'
  WHERE 
    h.rent IS NOT NULL 
),
prices_dataset AS (
  SELECT 
    id_house,
    id_house_listing,
    id_region,
    price,
    calculator_price,
    calculator_certainty,
    diff_calculator_price,
    FALSE AS is_actual,
    ts_price_started
  FROM 
    historical_prices
  UNION ALL 
  SELECT 
    id_house,
    id_house_listing,
    id_region,
    price,
    calculator_price,
    calculator_certainty,
    diff_calculator_price,
    TRUE AS is_actual,
    ts_price_started
  FROM 
    actual_prices
),
create_business_bins AS (
  SELECT 
    d.id_house, 
    d.id_house_listing,
    d.id_region, 
    CASE 
      WHEN d.calculator_certainty IS NULL THEN 'NONE'
      ELSE d.calculator_certainty 
    END AS certainty_calculator_bins, 
    CASE 
      WHEN d.calculator_price IS NULL OR d.calculator_price = 0 THEN 'T- Undefined'
      WHEN d.diff_calculator_price < -0.25 THEN 'T6 < -25%'
      WHEN d.diff_calculator_price BETWEEN -0.25 AND 0.00 THEN 'T5 (-25% | 0%]'
      WHEN d.diff_calculator_price BETWEEN 0.00 AND 0.15 THEN 'T4 (0% | 15%]'
      WHEN d.diff_calculator_price BETWEEN 0.15 AND 0.25 THEN 'T3 (15% | 25%]'
      WHEN d.diff_calculator_price BETWEEN 0.25 AND 0.50 THEN 'T2 (25% | 50%]'
      WHEN d.diff_calculator_price > 0.50 THEN 'T1 > 50%'
    END AS pricing_bins,
    d.is_actual,
    d.ts_price_started
  FROM
    prices_dataset AS d 
),
score_business_logic AS (
  SELECT
    id_house, 
    id_house_listing,
    id_region, 
    certainty_calculator_bins,
    pricing_bins,
    CASE 
      WHEN pricing_bins = 'T- Undefined' THEN 'P-'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]') AND certainty_calculator_bins = 'HIGH' THEN 'P5'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]') AND certainty_calculator_bins = 'MEDIUM' THEN 'P4'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]') THEN 'P3'
      WHEN pricing_bins = 'T4 (0% | 15%]' AND certainty_calculator_bins = 'HIGH' THEN 'P4'
      WHEN pricing_bins = 'T4 (0% | 15%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'P3'
      WHEN pricing_bins = 'T4 (0% | 15%]' THEN 'P2'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'HIGH' THEN 'P3'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'P2'
      WHEN pricing_bins = 'T3 (15% | 25%]' THEN 'P1'
      WHEN pricing_bins = 'T2 (25% | 50%]' AND certainty_calculator_bins = 'HIGH' THEN 'P2'
      WHEN pricing_bins = 'T2 (25% | 50%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'P1'
      ELSE 'P1'
    END AS tier,
    CASE 
      WHEN pricing_bins = 'T- Undefined' THEN 'The property does not have a set price in our calculator, we cannot rate a tier on it'   
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]') AND certainty_calculator_bins = 'HIGH' THEN 'The listings price is up to 25% below the calculators p50 predicted price and the prediction certainty is high.'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]') AND certainty_calculator_bins = 'MEDIUM' THEN 'The listings price is up to 25% below the calculators p50 predicted price and the prediction certainty is medium.'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]') THEN 'The listings price is up to 25% below the calculators p50 predicted price and the prediction certainty is low.'
      WHEN pricing_bins = 'T4 (0% | 15%]' AND certainty_calculator_bins = 'HIGH' THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is high.'
      WHEN pricing_bins = 'T4 (0% | 15%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is medium.'
      WHEN pricing_bins = 'T4 (0% | 15%]' THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is low.'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'HIGH' THEN 'The listings price is between 15% to 25% over the calculators p50 predicted price and the prediction certainty is high.'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'The listings price is between 15% to 25% over the calculators p50 predicted price and the prediction certainty is medium.'
      WHEN pricing_bins = 'T3 (15% | 25%]' THEN 'The listings price is between 15% to 25% over the calculators p50 predicted price and the prediction certainty is low.'
      WHEN pricing_bins = 'T2 (25% | 50%]' AND certainty_calculator_bins = 'HIGH' THEN 'The listings price is between 25% to 50% over the calculators p50 predicted price and the prediction certainty is high.'
      WHEN pricing_bins = 'T2 (25% | 50%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'The listings price is between 25% to 50% over the calculators p50 predicted price and the prediction certainty is medium.'
      WHEN pricing_bins = 'T2 (25% | 50%]' THEN 'The listings price is between 25% to 50% over the calculators p50 predicted price and the prediction certainty is low.'
      ELSE 'The listings price is 50% or more over the calculators p50 predicted price.'
    END AS tier_disclaimer,
    is_actual,
    ts_price_started
  FROM 
    create_business_bins
),
grouping_tiers AS (
  SELECT 
    id_house, 
    id_house_listing,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    is_actual,
    ts_price_started AS ts_tier_started
  FROM
    score_business_logic
  QUALIFY 
    tier IS DISTINCT FROM LAG(tier) OVER (PARTITION BY id_house ORDER BY ts_price_started)
    OR is_actual = TRUE
),
check_to_filter_the_current_photo_as_the_last_tier AS (
  SELECT 
    id_house,
    id_house_listing,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    is_actual,
    ROW_NUMBER() OVER (PARTITION BY id_house, is_actual ORDER BY ts_tier_started DESC) = 1 AS is_check,
    ts_tier_started
  FROM 
    grouping_tiers
),
filtering_the_current_photo_as_the_last_tier AS (
  SELECT 
    id_house,
    id_house_listing,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    is_actual,
    LAG(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started ASC) AS ts_tier_started
  FROM 
    check_to_filter_the_current_photo_as_the_last_tier
  WHERE 
    is_check IS TRUE 
), 
corrected_history AS (
  SELECT
    id_house,
    id_house_listing,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    ts_tier_started
  FROM
    check_to_filter_the_current_photo_as_the_last_tier 
  WHERE 
    is_check IS FALSE
  UNION ALL 
  SELECT 
    id_house,
    id_house_listing,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    ts_tier_started
  FROM
    filtering_the_current_photo_as_the_last_tier
  WHERE 
    is_actual IS TRUE
),
aux AS (
  SELECT 
    id_house,
    id_house_listing,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    CASE  
      WHEN tier = 'P5' THEN 'Great Price'
      WHEN tier = 'P4' THEN 'Good Price'
      WHEN tier = 'P3' THEN 'Fair Price'
      WHEN tier = 'P2' THEN 'Slightly Overpriced '
      WHEN tier = 'P1' THEN 'Significantly Overpriced'
      WHEN tier = 'P-' THEN 'Undefined'
    END AS tier_name,
    tier_disclaimer,
    TO_DATE(ts_tier_started) AS ts_tier_started,
    TO_DATE(LEAD(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started)) AS ts_tier_ended
  FROM
    corrected_history
  WHERE 
    ts_tier_started IS NOT NULL 
)
SELECT 
  id_house, 
  id_house_listing,
  id_region,
  pricing_bins,
  certainty_calculator_bins,
  tier,
  tier_name,
  tier_disclaimer,
  ts_tier_ended IS NULL AS is_last_tier,
  ts_tier_started,
  DATE_SUB(ts_tier_ended, 1) AS ts_tier_ended
FROM
  aux