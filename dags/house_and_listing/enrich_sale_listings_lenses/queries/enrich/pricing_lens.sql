WITH historical_prices AS (
  SELECT
    id_house,
    id_region,
    sale_price,
    calculator_sale_price,
    calculator_certainty,
    (
      sale_price / calculator_sale_price
    ) - 1 AS diff_calculator_price,
    ts_price_started
  FROM datalake_sale_listings.sale_listing_price_changes
),
actual_prices AS (
  SELECT
    h.id AS id_house,
    h.id_region,
    h.sale_price,
    p.p_50 AS calculator_sale_price,
    p.certainty AS calculator_certainty,
    (
      h.sale_price / p.p_50
    ) - 1. AS diff_calculator_price,
    CURRENT_TIMESTAMP() AS ts_price_started
  FROM datalake_ebdb_listing.house AS h
  LEFT JOIN datalake_ebdb_clean.house_predicted_price AS p
    ON h.id = p.id_house AND p.business_context = 'SALE'
  WHERE
    NOT h.sale_price IS NULL AND h.sale_price > 0
),
prices_dataset AS (
  SELECT
    id_house,
    id_region,
    sale_price,
    calculator_sale_price,
    calculator_certainty,
    diff_calculator_price,
    FALSE AS is_actual,
    ts_price_started
  FROM historical_prices
  UNION ALL
  SELECT
    id_house,
    id_region,
    sale_price,
    calculator_sale_price,
    calculator_certainty,
    diff_calculator_price,
    TRUE AS is_actual,
    ts_price_started
  FROM actual_prices
),
great_price_tag_status_by_day_ranked AS (
  SELECT
    lbc.id_house,
    l.has_great_sale_price_tag,
    r.ts_revision AS ts_change,
    ROW_NUMBER() OVER (PARTITION BY lbc.id_house, DATE_TRUNC('DAY', r.ts_revision) ORDER BY rev DESC) AS rn
  FROM datalake_ebdb_clean.listing_sale_model_aud AS l
  INNER JOIN datalake_ebdb_user.user_revision_entity AS r
    ON l.rev = r.id
  INNER JOIN datalake_ebdb_clean.listing_business_context AS lbc
    ON lbc.id = l.id_listing_business_context
  WHERE
    lbc.business_context = 'SALE'
),
great_price_tag_status_by_day AS (
  SELECT
    id_house,
    has_great_sale_price_tag,
    ts_change
  FROM great_price_tag_status_by_day_ranked
  WHERE
    rn = 1
),
great_price_tag_status_aux_with_lag AS (
  SELECT
    id_house,
    has_great_sale_price_tag,
    ts_change,
    LAG(has_great_sale_price_tag) OVER (PARTITION BY id_house ORDER BY ts_change ASC) AS prev_has_great_sale_price_tag
  FROM great_price_tag_status_by_day
),
great_price_tag_status_aux AS (
  SELECT
    id_house,
    has_great_sale_price_tag,
    ts_change
  FROM great_price_tag_status_aux_with_lag
  WHERE
    prev_has_great_sale_price_tag IS DISTINCT FROM has_great_sale_price_tag
),
great_price_tag_status AS (
  SELECT
    id_house,
    has_great_sale_price_tag,
    DATE_TRUNC('DAY', ts_change) AS dt_change,
    DATE_TRUNC('DAY', LEAD(ts_change) OVER (PARTITION BY id_house ORDER BY ts_change)) AS dt_next_change,
    ts_change
  FROM great_price_tag_status_aux
),
create_business_bins_ranked AS (
  SELECT
    d.id_house,
    d.id_region,
    CASE WHEN d.calculator_certainty IS NULL THEN 'NONE' ELSE d.calculator_certainty END AS certainty_calculator_bins,
    CASE
      WHEN d.calculator_sale_price IS NULL OR d.calculator_sale_price = 0
      THEN 'T- Undefined'
      WHEN d.diff_calculator_price < -0.25
      THEN 'T6 < -25%'
      WHEN d.diff_calculator_price BETWEEN -0.25 AND 0.00
      THEN 'T5 (-25% | 0%]'
      WHEN d.diff_calculator_price BETWEEN 0.00 AND 0.15
      THEN 'T4 (0% | 15%]'
      WHEN d.diff_calculator_price BETWEEN 0.15 AND 0.25
      THEN 'T3 (15% | 25%]'
      WHEN d.diff_calculator_price BETWEEN 0.25 AND 0.50
      THEN 'T2 (25% | 50%]'
      WHEN d.diff_calculator_price > 0.50
      THEN 'T1 > 50%'
    END AS pricing_bins,
    COALESCE(t.has_great_sale_price_tag, FALSE) AS has_great_price_tag,
    d.is_actual,
    d.ts_price_started,
    ROW_NUMBER() OVER (PARTITION BY d.id_house, d.ts_price_started ORDER BY t.ts_change ASC) AS rn
  FROM prices_dataset AS d
  LEFT JOIN great_price_tag_status AS t
    ON d.id_house = t.id_house
    AND DATE_TRUNC('DAY', d.ts_price_started) BETWEEN t.dt_change AND COALESCE(t.dt_next_change, CURRENT_TIMESTAMP())
),
create_business_bins AS (
  SELECT
    id_house,
    id_region,
    certainty_calculator_bins,
    pricing_bins,
    has_great_price_tag,
    is_actual,
    ts_price_started
  FROM create_business_bins_ranked
  WHERE
    rn = 1
),
score_business_logic AS (
  SELECT
    id_house,
    id_region,
    certainty_calculator_bins,
    pricing_bins,
    CASE
      WHEN has_great_price_tag = TRUE
      THEN 'P5'
      WHEN pricing_bins = 'T- Undefined'
      THEN 'P-'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]')
      AND certainty_calculator_bins = 'HIGH'
      THEN 'P5'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]')
      AND certainty_calculator_bins = 'MEDIUM'
      THEN 'P4'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]')
      THEN 'P3'
      WHEN pricing_bins = 'T4 (0% | 15%]' AND certainty_calculator_bins = 'HIGH'
      THEN 'P4'
      WHEN pricing_bins = 'T4 (0% | 15%]' AND certainty_calculator_bins = 'MEDIUM'
      THEN 'P3'
      WHEN pricing_bins = 'T4 (0% | 15%]'
      THEN 'P2'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'HIGH'
      THEN 'P3'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'MEDIUM'
      THEN 'P2'
      WHEN pricing_bins = 'T3 (15% | 25%]'
      THEN 'P1'
      WHEN pricing_bins = 'T2 (25% | 50%]' AND certainty_calculator_bins = 'HIGH'
      THEN 'P2'
      WHEN pricing_bins = 'T2 (25% | 50%]' AND certainty_calculator_bins = 'MEDIUM'
      THEN 'P1'
      ELSE 'P1'
    END AS tier,
    CASE
      WHEN has_great_price_tag = TRUE
      THEN 'The listing has the great price tag currently active.'
      WHEN pricing_bins = 'T- Undefined'
      THEN 'The property does not have a set price in our calculator, we cannot rate a tier on it'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]')
      AND certainty_calculator_bins = 'HIGH'
      THEN 'The listings price is up to 25% below the calculators p50 predicted price and the prediction certainty is high.'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]')
      AND certainty_calculator_bins = 'MEDIUM'
      THEN 'The listings price is up to 25% below the calculators p50 predicted price and the prediction certainty is medium.'
      WHEN pricing_bins IN ('T6 < -25%', 'T5 (-25% | 0%]')
      THEN 'The listings price is up to 25% below the calculators p50 predicted price and the prediction certainty is low.'
      WHEN pricing_bins = 'T4 (0% | 15%]' AND certainty_calculator_bins = 'HIGH'
      THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is high.'
      WHEN pricing_bins = 'T4 (0% | 15%]' AND certainty_calculator_bins = 'MEDIUM'
      THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is medium.'
      WHEN pricing_bins = 'T4 (0% | 15%]'
      THEN 'The property is up to 0%-15% above P50 and the predicted price certainty is low.'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'HIGH'
      THEN 'The listings price is between 15% to 25% over the calculators p50 predicted price and the prediction certainty is high.'
      WHEN pricing_bins = 'T3 (15% | 25%]' AND certainty_calculator_bins = 'MEDIUM'
      THEN 'The listings price is between 15% to 25% over the calculators p50 predicted price and the prediction certainty is medium.'
      WHEN pricing_bins = 'T3 (15% | 25%]'
      THEN 'The listings price is between 15% to 25% over the calculators p50 predicted price and the prediction certainty is low.'
      WHEN pricing_bins = 'T2 (25% | 50%]' AND certainty_calculator_bins = 'HIGH'
      THEN 'The listings price is between 25% to 50% over the calculators p50 predicted price and the prediction certainty is high.'
      WHEN pricing_bins = 'T2 (25% | 50%]' AND certainty_calculator_bins = 'MEDIUM'
      THEN 'The listings price is between 25% to 50% over the calculators p50 predicted price and the prediction certainty is medium.'
      WHEN pricing_bins = 'T2 (25% | 50%]'
      THEN 'The listings price is between 25% to 50% over the calculators p50 predicted price and the prediction certainty is low.'
      ELSE 'The listings price is 50% or more over the calculators p50 predicted price.'
    END AS tier_disclaimer,
    has_great_price_tag,
    is_actual,
    ts_price_started
  FROM create_business_bins
),
grouping_tiers_with_lag AS (
  SELECT
    id_house,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    has_great_price_tag,
    is_actual,
    ts_price_started AS ts_tier_started,
    LAG(tier) OVER (PARTITION BY id_house ORDER BY ts_price_started) AS prev_tier
  FROM score_business_logic
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
    is_actual,
    ts_tier_started
  FROM grouping_tiers_with_lag
  WHERE
    tier IS DISTINCT FROM prev_tier OR is_actual = TRUE
),
check_to_filter_the_current_photo_as_the_last_tier AS (
  SELECT
    id_house,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    has_great_price_tag,
    is_actual,
    ROW_NUMBER() OVER (PARTITION BY id_house, is_actual ORDER BY ts_tier_started DESC) = 1 AS is_check,
    ts_tier_started
  FROM grouping_tiers
),
filtering_the_current_photo_as_the_last_tier AS (
  SELECT
    id_house,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    has_great_price_tag,
    is_actual,
    LAG(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started ASC) AS ts_tier_started
  FROM check_to_filter_the_current_photo_as_the_last_tier
  WHERE
    is_check IS TRUE
),
corrected_history AS (
  SELECT
    id_house,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    has_great_price_tag,
    ts_tier_started
  FROM check_to_filter_the_current_photo_as_the_last_tier
  WHERE
    is_check IS FALSE
  UNION ALL
  SELECT
    id_house,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    tier_disclaimer,
    has_great_price_tag,
    ts_tier_started
  FROM filtering_the_current_photo_as_the_last_tier
  WHERE
    is_actual IS TRUE
),
aux AS (
  SELECT
    id_house,
    id_region,
    pricing_bins,
    certainty_calculator_bins,
    tier,
    CASE
      WHEN tier = 'P5'
      THEN 'Great Price'
      WHEN tier = 'P4'
      THEN 'Good Price'
      WHEN tier = 'P3'
      THEN 'Fair Price'
      WHEN tier = 'P2'
      THEN 'Slightly Overpriced '
      WHEN tier = 'P1'
      THEN 'Significantly Overpriced'
      WHEN tier = 'P-'
      THEN 'Undefined'
    END AS tier_name,
    tier_disclaimer,
    has_great_price_tag,
    TO_DATE(ts_tier_started) AS ts_tier_started,
    TO_DATE(LEAD(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started)) AS ts_tier_ended
  FROM corrected_history
  WHERE
    NOT ts_tier_started IS NULL
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
  DATE_ADD(ts_tier_ended, 1 * -1) AS ts_tier_ended
FROM aux