WITH historical_prices AS (
  SELECT 
    id_house, 
    id_region, 
    sale_price,
    calculator_sale_price,
    calculator_certainty,
    (sale_price / calculator_sale_price) -1 AS diff_calculator_price,
    ts_price_started
  FROM 
    datalake_sale_listings.sale_listing_price_changes
),
great_price_tag_status_by_day AS ( 
  SELECT 
    lbc.id_house,
    l.has_great_sale_price_tag,
    r.ts_revision AS ts_change
  FROM 
    datalake_ebdb_clean.listing_sale_model_aud AS l
  INNER JOIN
    datalake_ebdb_user.user_revision_entity AS r
      ON l.rev = r.id
  INNER JOIN 
    datalake_ebdb_clean.listing_business_context AS lbc
      ON lbc.id = l.id_listing_business_context
  WHERE 
    lbc.business_context = 'SALE'
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY lbc.id_house, DATE_TRUNC('DAY', r.ts_revision) ORDER BY rev DESC) = 1
),
great_price_tag_status_aux AS (
  SELECT 
    id_house,
    has_great_sale_price_tag,
    ts_change
  FROM
    great_price_tag_status_by_day
  QUALIFY 
    LAG(has_great_sale_price_tag) OVER (PARTITION BY id_house ORDER BY ts_change ASC) IS DISTINCT FROM has_great_sale_price_tag
),
great_price_tag_status AS (
  SELECT
    id_house,
    has_great_sale_price_tag,
    DATE_TRUNC('DAY', ts_change) AS dt_change,
    DATE_TRUNC('DAY', LEAD(ts_change) OVER (PARTITION BY id_house ORDER BY ts_change)) AS dt_next_change,
    ts_change
  FROM
    great_price_tag_status_aux
),
create_business_bins AS (
  SELECT 
    hp.id_house, 
    hp.id_region, 
    CASE 
      WHEN hp.calculator_certainty IS NULL THEN 'NONE'
      ELSE hp.calculator_certainty 
    END AS certainty_calculator_bins, 
    CASE 
      WHEN hp.calculator_sale_price IS NULL THEN 'T- Undefined'
      WHEN hp.diff_calculator_price < -0.25 THEN 'T6 < -25%'
      WHEN hp.diff_calculator_price BETWEEN -0.25 AND 0.00 THEN 'T5 (-25% | 0%]'
      WHEN hp.diff_calculator_price BETWEEN 0.00 AND 0.15 THEN 'T4 (0% | 15%]'
      WHEN hp.diff_calculator_price BETWEEN 0.15 AND 0.25 THEN 'T3 (15% | 25%]'
      WHEN hp.diff_calculator_price BETWEEN 0.25 AND 0.50 THEN 'T2 (25% | 50%]'
      WHEN hp.diff_calculator_price > 0.50 THEN 'T1 > 50%'
    END AS pricing_bins,
    COALESCE(has_great_sale_price_tag, FALSE) AS has_great_price_tag,
    hp.ts_price_started
  FROM
    historical_prices AS hp 
  LEFT JOIN 
    great_price_tag_status AS pt 
      ON hp.id_house = pt.id_house
      AND DATE_TRUNC('DAY', hp.ts_price_started) BETWEEN pt.dt_change AND COALESCE(pt.dt_next_change, CURRENT_TIMESTAMP)
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY hp.id_house, hp.ts_price_started ORDER BY pt.ts_change ASC) = 1 
),
score_business_logic AS (
  SELECT
    id_house, 
    id_region, 
    certainty_calculator_bins,
    pricing_bins,
    CASE 
      WHEN has_great_price_tag = TRUE THEN 'P5'    
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
      WHEN has_great_price_tag = TRUE THEN 'The listing has the great price tag currently active.'  
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
    has_great_price_tag,
    ts_price_started
  FROM 
    create_business_bins
),
grouping_tiers AS (
  SELECT 
    id_house, 
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    has_great_price_tag,
    ts_price_started AS ts_tier_started
  FROM
    score_business_logic
  QUALIFY 
    ts_price_started = MIN(ts_price_started) OVER (PARTITION BY id_house) 
    OR tier != LAG(tier) OVER (PARTITION BY id_house ORDER BY ts_price_started) 
),
aux AS (
  SELECT 
    id_house, 
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
    has_great_price_tag,
    TO_DATE(ts_tier_started) AS ts_tier_started,
    TO_DATE(LEAD(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started)) AS ts_tier_ended
  FROM
    grouping_tiers
)
SELECT 
  id_house, 
  id_region,
  pricing_bins,
  certainty_calculator_bins,
  tier,
  tier_name,
  tier_disclaimer,
  has_great_price_tag,
  ts_tier_ended IS NULL AS is_last_tier,
  ts_tier_started,
  DATE_SUB(ts_tier_ended, 1) AS ts_tier_ended
FROM
  aux