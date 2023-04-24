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
great_price_tag_status_aux AS ( 
  SELECT 
    lbc.id_house,
    has_great_sale_price_tag,
    FROM_UNIXTIME(r.ts_revision/1000) AS ts_change
  FROM 
    datalake_ebdb_clean.listing_sale_model_aud AS l
  INNER JOIN
    datalake_ebdb_clean.user_revision_entity AS r
      ON l.rev = r.id
  INNER JOIN 
    datalake_ebdb_clean.listing_business_context AS lbc
      ON lbc.id = l.id_listing_business_context
  WHERE 
    lbc.business_context = 'SALE'
  QUALIFY 
    LAG(has_great_sale_price_tag) OVER (PARTITION BY id_house ORDER BY FROM_UNIXTIME(r.ts_revision/1000) ASC) IS DISTINCT FROM has_great_sale_price_tag
),
great_price_tag_status AS (
  SELECT 
    id_house,
    has_great_sale_price_tag,
    ts_change,
    LEAD(ts_change) OVER (PARTITION BY id_house ORDER BY ts_change) AS ts_next_change
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
      WHEN hp.calculator_sale_price IS NULL THEN 'TXX Undefined'
      WHEN hp.diff_calculator_price < -0.25 THEN 'T0 < -25%'
      WHEN hp.diff_calculator_price BETWEEN -0.25 AND 0.00 THEN 'T1 (-25% | 0%]'
      WHEN hp.diff_calculator_price BETWEEN 0.00 AND 0.15 THEN 'T2 (0% | 15%]'
      WHEN hp.diff_calculator_price BETWEEN 0.15 AND 0.25 THEN 'T3 (15% | 25%]'
      WHEN hp.diff_calculator_price BETWEEN 0.25 AND 0.50 THEN 'T4 (25% | 50%]'
      WHEN hp.diff_calculator_price > 0.50 THEN 'T5 > 50%'
    END AS pricing_bins,
    has_great_sale_price_tag AS has_great_price_tag,
    hp.ts_price_started
  FROM
    historical_prices AS hp 
  LEFT JOIN 
    great_price_tag_status AS pt 
      ON hp.id_house = pt.id_house
      AND hp.ts_price_started BETWEEN pt.ts_change AND COALESCE(pt.ts_next_change, CURRENT_TIMESTAMP)
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
      WHEN has_great_price_tag = TRUE THEN 'P0'    
      WHEN pricing_bins = 'TXX Undefined' THEN 'P Undefined'
      WHEN pricing_bins IN ('T0 < -25%', 'T1 (-25% | 0%]') AND certainty_calculator_bins = 'HIGH' THEN 'P0'
      WHEN pricing_bins IN ('T0 < -25%', 'T1 (-25% | 0%]') AND certainty_calculator_bins = 'MEDIUM' THEN 'P1'
      WHEN pricing_bins IN ('T0 < -25%', 'T1 (-25% | 0%]') THEN 'P2'
      WHEN pricing_bins = 'T2 (0% | 15%]' AND certainty_calculator_bins = 'HIGH' THEN 'P1'
      WHEN pricing_bins = 'T2 (0% | 15%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'P2'
      WHEN pricing_bins = 'T2 (0% | 15%]' THEN 'P3'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'HIGH' THEN 'P2'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'P3'
      WHEN pricing_bins = 'T3 (15% | 25%]' THEN 'P4'
      WHEN pricing_bins = 'T4 (25% | 50%]' AND certainty_calculator_bins = 'HIGH' THEN 'P3'
      WHEN pricing_bins = 'T4 (25% | 50%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'P4'
      ELSE 'P4'
    END AS tier,
    CASE 
      WHEN has_great_price_tag = TRUE THEN 'The listing has great price tag active'  
      WHEN pricing_bins = 'TXX Undefined' THEN 'The property does not have a set price in our calculator, we cannot rate a tier on it'   
      WHEN pricing_bins IN ('T0 < -25%', 'T1 (-25% | 0%]') AND certainty_calculator_bins = 'HIGH' THEN 'The property is up to 25%-0% below P50 and the predicted price certainty is high'
      WHEN pricing_bins IN ('T0 < -25%', 'T1 (-25% | 0%]') AND certainty_calculator_bins = 'MEDIUM' THEN 'The property is up to 25%-0% below P50 and the predicted price certainty is medium'
      WHEN pricing_bins IN ('T0 < -25%', 'T1 (-25% | 0%]') THEN 'The property is up to 25%-0% below P50 and the predicted price certainty is low'
      WHEN pricing_bins = 'T2 (0% | 15%]' AND certainty_calculator_bins = 'HIGH' THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is high'
      WHEN pricing_bins = 'T2 (0% | 15%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is medium'
      WHEN pricing_bins = 'T2 (0% | 15%]' THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is low'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'HIGH' THEN 'The property is up to 15%-25% above P50 and the predicted price certainty is high'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'The property is up to 15%-25% above P50 and the predicted price certainty is medium'
      WHEN pricing_bins = 'T3 (15% | 25%]' THEN 'The property is up to 15%-25% above P50 and the predicted price certainty is low'
      WHEN pricing_bins = 'T4 (25% | 50%]' AND certainty_calculator_bins = 'HIGH' THEN 'The property is up to 25%-50% above P50 and the predicted price certainty is high'
      WHEN pricing_bins = 'T4 (25% | 50%]' AND certainty_calculator_bins = 'MEDIUM' THEN 'The property is up to 25%-50% above P50 and the predicted price certainty is medium'
      ELSE 'The property is up to 50% above P50'
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
)
SELECT 
  id_house, 
  id_region,
  pricing_bins,
  certainty_calculator_bins,
  tier,
  CASE  
    WHEN tier = 'P0' THEN 'Excellent Price'
    WHEN tier = 'P1' THEN 'Great Price'
    WHEN tier = 'P2' THEN 'Fair Price'
    WHEN tier = 'P3' THEN 'Slightly Overpriced '
    WHEN tier = 'P4' THEN 'Significantly Overpriced'
    WHEN tier = 'P Undefined' THEN 'Undefined'
  END AS tier_name,
  tier_disclaimer,
  has_great_price_tag,
  ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_tier_started DESC) = 1 AS is_last_tier,
  ts_tier_started,
  LEAD(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started) AS ts_score_ended
FROM
  grouping_tiers