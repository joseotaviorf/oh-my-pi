WITH pricing_bins AS (
  SELECT
    1 AS id_bin,
    'price' AS bin,
    "T00 [120k-300k]" AS tag,
    1 AS order,
    120000 AS lower_band,
    300000 AS upper_band
  UNION ALL
  SELECT
    1,
    'price',
    'T01 [300k-500k]',
    2, 
    300000,
    500000
  UNION ALL
  SELECT
    1,
    'price',
    'T02 [500k-700k]',
    3,
    500000,
    700000
  UNION ALL 
  SELECT
    1,
    'price',
    'T03 [700k-900k]',
    4,
    700000,
    900000
  UNION ALL 
  SELECT 
    1,
    'price',
    'T04 [900k-1.2M]',
    5,
    900000,
    1200000
  UNION ALL 
  SELECT 
    1,
    'price',
    'T05 [1.2M-1.6M]',
    6,
    1200000,
    1600000
  UNION ALL 
  SELECT
    1,
    'price',
    'T06 [1.6M-2M]',
    7,
    1600000,
    2000000
  UNION ALL 
  SELECT
    1,
    'price',
    'T07 [2M-2.5M]',
    8,
    2000000,
    2500000
  UNION ALL 
  SELECT 
    1,
    'price',
    'T08 [2.5M-4M]',
    9,
    2500000,
    4000000
  UNION ALL 
  SELECT 
    1,
    'price',
    'T09 [4M-20M]',
    10,
    4000000,
    20000000
  UNION ALL
  SELECT 
    1,
    'price',
    'TXX Undefined',
    11,
    null,
    null
),
pricing_m2_bins AS (
  SELECT 
    2 AS id_bin,
    'price_m2' AS bin,
    'TA00 [0k-3k]' AS tag,
    1 AS order,
    0 AS lower_band,
    3000 AS upper_band
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA01 [3k-4k]',
    2,
    3000,
    4000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA02 [4k-5k]',
    3,
    4000,
    5000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA03 [5k-6k]',
    4,
    5000,
    6000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA04 [6k-7k]',
    5,
    6000,
    7000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA05 [7k-8k]',
    6,
    7000,
    8000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA06 [8k-9k]',
    7,
    8000,
    9000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA07 [9k-12k]',
    8,
    9000,
    12000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA08 [12k-15k]',
    9,
    12000,
    15000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'TA09 [>18k]',
    10,
    15000,
    999999999
  UNION ALL
  SELECT 
    2,
    'price_m2',
    'TXX Undefined',
    11,
    null,
    null
),
total_area_bins AS (
  SELECT 
    3 AS id_bin,
    'total_area' AS bin,
    'TA01 [50m]' AS tag,
    1 AS order,
    5 AS lower_band,
    50 AS upper_band
  UNION ALL
  SELECT
    3,
    'total_area',
    'TA02 [50m-80m]',
    2,
    50,
    80
  UNION ALL
  SELECT
    3 ,
    'total_area',
    'TA03 [80m-120m]',
    3,
    80,
    120
  UNION ALL
  SELECT
    3 ,
    'total_area',
    'TA04 [>120m]',
    4,
    120,
    999999999
  UNION ALL
  SELECT
    3 ,
    'total_area',
    'TXX Undefined',
    5,
    null,
    null
)
SELECT 
  id_bin,
  bin,
  tag,
  order,
  lower_band,
  upper_band
FROM 
  pricing_bins
UNION ALL
SELECT 
  id_bin,
  bin,
  tag,
  order,
  lower_band,
  upper_band
FROM
  pricing_m2_bins
UNION ALL
SELECT 
  id_bin,
  bin,
  tag,
  order,
  lower_band,
  upper_band
FROM
  total_area_bins