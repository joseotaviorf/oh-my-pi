WITH historical_prices AS (
  SELECT 
    pc.id_house, 
    pc.id_region, 
    pc.sale_price,
    pc.sale_price/h.total_area AS sale_price_m2,
    pc.ts_price_started
  FROM 
    datalake_sale_listings.sale_listing_price_changes AS pc
  LEFT JOIN 
    datalake_ebdb_clean.house AS h
      ON h.id = pc.id_house
  WHERE 
    h.total_area IS NOT NULL AND h.total_area > 0 
),
create_business_bins AS (
  SELECT 
    id_house,
    id_region,
    sale_price,
    sale_price_m2,
    CASE 
      WHEN sale_price < 300000 THEN "T00 [120k-300k)"
      WHEN sale_price >= 300000 AND sale_price < 500000 THEN "T01 [300k-500k)"
      WHEN sale_price >= 500000 AND sale_price < 700000 THEN "T02 [500k-700k)"
      WHEN sale_price >= 700000 AND sale_price < 900000 THEN "T03 [700k-900k)"
      WHEN sale_price >= 900000 AND sale_price < 1200000 THEN "T04 [900k-1.2M)"
      WHEN sale_price >= 1200000 AND sale_price < 1600000 THEN "T05 [1.2M-1.6M)"
      WHEN sale_price >= 1600000 AND sale_price < 2000000 THEN "T06 [1.6M-2M)"
      WHEN sale_price >= 2000000 AND sale_price < 2500000 THEN "T07 [2M-2.5M)"
      WHEN sale_price >= 2500000 AND sale_price <= 20000000  THEN "T08 [2.5M,20M]"
      ELSE "TXX Undefined" 
    END AS sale_price_bins,
    CASE 
      WHEN sale_price_m2 < 5000 THEN 'TA00 [0k-5k)'
      WHEN sale_price_m2 >= 5000 AND sale_price_m2 < 10000 THEN 'TA01 [5k-10k)'
      WHEN sale_price_m2 >= 10000 AND sale_price_m2 < 15000 THEN 'TA02 [10k-15k)'
      WHEN sale_price_m2 >= 15000 AND sale_price_m2 < 20000 THEN 'TA03 [15k-20k)'
      WHEN sale_price_m2 >= 20000 THEN 'TA04 >20k'
    END AS sale_price_m2_bins,
    ts_price_started
  FROM
    historical_prices
),
score_business_logic AS (
  SELECT 
    id_house, 
    id_region,
    sale_price_bins,
    sale_price_m2_bins,
    CASE 
      WHEN sale_price_bins = 'TXX Undefined' THEN 'P Undefined'
      WHEN sale_price_bins IN ('T00 [120k-300k)', 'T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA00 [0k-5k)' THEN 'P4'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA00 [0k-5k)' THEN 'P4'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA00 [0k-5k)' THEN 'P3'
      WHEN sale_price_bins IN ('T00 [120k-300k)', 'T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA01 [5k-10k)' THEN 'P4'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA01 [5k-10k)' THEN 'P3'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA01 [5k-10k)' THEN 'P2'
      WHEN sale_price_bins IN ('T00 [120k-300k)') AND sale_price_m2_bins = 'TA02 [10k-15k)'THEN 'P4'
      WHEN sale_price_bins IN ('T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA02 [10k-15k)' THEN 'P3'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA02 [10k-15k)' THEN 'P2'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA02 [10k-15k)' THEN 'P1'
      WHEN sale_price_bins IN ('T00 [120k-300k)') AND sale_price_m2_bins = 'TA03 [15k-20k)' THEN 'P4'
      WHEN sale_price_bins IN ('T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA03 [15k-20k)' THEN 'P3'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA03 [15k-20k)' THEN 'P2'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA03 [15k-20k)' THEN 'P1'
      WHEN sale_price_bins IN ('T00 [120k-300k)') AND sale_price_m2_bins = 'TA04 >20k' THEN 'P3'
      WHEN sale_price_bins IN ('T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA04 >20k' THEN 'P2'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA04 >20k' THEN 'P1'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA04 >20k' THEN 'P0'
    END AS tier,
    CASE 
      WHEN sale_price_bins = 'TXX Undefined' THEN 'We do not have the information on the price component of this listing, so we are unable to gauge a tier.'
      WHEN sale_price_bins IN ('T00 [120k-300k)', 'T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA00 [0k-5k)' THEN 'The listing has a price per M2 at least 5k and listing sale price between 120k and 700k'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA00 [0k-5k)' THEN 'The listing has a price per M2 at least 5k and listing sale price between 700k and 1.6M'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA00 [0k-5k)' THEN 'The listing has a price per M2 at least 5k and listing sale price between 1.6M and 20M'
      WHEN sale_price_bins IN ('T00 [120k-300k)', 'T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA01 [5k-10k)' THEN 'The listing has a price per M2 between 5k-10k and listing sale price between 120k and 700k'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA01 [5k-10k)' THEN 'The listing has a price per M2 between 5k-10k and listing sale price between 700k and 1.6M'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA01 [5k-10k)' THEN 'The listing has a price per M2 between 5k-10k and listing sale price between 1.6M and 20M'
      WHEN sale_price_bins IN ('T00 [120k-300k)') AND sale_price_m2_bins = 'TA02 [10k-15k)'THEN 'The listing has a high price per M2 between 10k-15k and listing sale price at least 300k'
      WHEN sale_price_bins IN ('T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA02 [10k-15k)' THEN 'The listing has a high price per M2 between 10k-15k and listing sale price between 300k and 700k'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA02 [10k-15k)' THEN 'The listing has a high price per M2 between 10k-15k and listing sale price between 700K and 1.6M' 
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA02 [10k-15k)' THEN 'The listing has a high price per M2 between 10k-15k and listing sale price between 1.6M and 20M' 
      WHEN sale_price_bins IN ('T00 [120k-300k)') AND sale_price_m2_bins = 'TA03 [15k-20k)' THEN 'The listing has a high price per M2 between 10k-15k and listing sale price at least 300k' 
      WHEN sale_price_bins IN ('T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA03 [15k-20k)' THEN 'The listing has a high price per M2 between 15k-20k and listing sale price between 300K and 700K'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA03 [15k-20k)' THEN 'The listing has a high price per M2 between 15k-20k and listing sale price between 700K and 1.6M'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA03 [15k-20k)' THEN 'The listing has a high price per M2 between 15k-20k and listing sale price between 1.6M and 20M'
      WHEN sale_price_bins IN ('T00 [120k-300k)') AND sale_price_m2_bins = 'TA04 >20k' THEN 'The listing has a high price per M2 - more than 20k and listing sale price at least 300k'
      WHEN sale_price_bins IN ('T01 [300k-500k)', 'T02 [500k-700k)') AND sale_price_m2_bins = 'TA04 >20k' THEN 'The listing has a high price per M2 - more than 20k and listing sale price between 300k and 700k'
      WHEN sale_price_bins IN ('T03 [700k-900k)', 'T04 [900k-1.2M)', 'T05 [1.2M-1.6M)') AND sale_price_m2_bins = 'TA04 >20k' THEN 'The listing has a high price per M2 - more than 20k and listing sale price between 700k and 1.6k'
      WHEN sale_price_bins IN ('T06 [1.6M-2M)', 'T07 [2M-2.5M)', 'T08 [2.5M,20M]') AND sale_price_m2_bins = 'TA04 >20k' THEN 'The listing has a high price per M2 - more than 20k and listing sale price between 1.6M and 20M'
    END AS tier_disclaimer,
    ts_price_started
  FROM
    create_business_bins
  WHERE 
    id_region IN (45, 46, 47, 49, 51, 52, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 68, 69, 70, 71, 72, 73, 1281, 1282, 1283, 1284, 1285, 1286, 1287, 1299, 1329, 1588, 4942, 4986)
),
grouping_tiers AS (
  SELECT 
    id_house, 
    id_region,
    sale_price_bins AS price_bins,
    sale_price_m2_bins AS price_m2_bins,
    tier,
    tier_disclaimer,
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
  price_bins,
  price_m2_bins,
  tier,
  CASE    
    WHEN tier = 'P0' THEN 'High End Premium'
    WHEN tier = 'P1' THEN 'High Premium'
    WHEN tier = 'P2' THEN 'Standard Premium'
    WHEN tier = 'P3' THEN 'Simple Premium'
    WHEN tier = 'P4' THEN 'Basic Premium'
  END AS tier_name,
  tier_disclaimer,
  ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_tier_started DESC) = 1 AS is_last_tier,
  ts_tier_started,
  LEAD(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started) AS ts_score_ended
FROM
  grouping_tiers