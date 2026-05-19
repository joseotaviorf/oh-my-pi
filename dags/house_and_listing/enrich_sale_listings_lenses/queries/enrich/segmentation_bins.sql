WITH pricing_bins AS (
  SELECT
    1 AS id_bin,
    'price' AS bin,
    "R$ 120k-300k" AS tag,
    1 AS order,
    120000 AS lower_band,
    300000 AS upper_band
  UNION ALL
  SELECT
    1,
    'price',
    'R$ 300k-500k',
    2, 
    300000,
    500000
  UNION ALL
  SELECT
    1,
    'price',
    'R$ 500k-700k',
    3,
    500000,
    700000
  UNION ALL 
  SELECT
    1,
    'price',
    'R$ 700k-900k',
    4,
    700000,
    900000
  UNION ALL 
  SELECT 
    1,
    'price',
    'R$ 900k-1.2M',
    5,
    900000,
    1200000
  UNION ALL 
  SELECT 
    1,
    'price',
    'R$ 1.2M-1.6M',
    6,
    1200000,
    1600000
  UNION ALL 
  SELECT
    1,
    'price',
    'R$ 1.6M-2M',
    7,
    1600000,
    2000000
  UNION ALL 
  SELECT
    1,
    'price',
    'R$ 2M-2.5M',
    8,
    2000000,
    2500000
  UNION ALL 
  SELECT 
    1,
    'price',
    'R$ 2.5M-4M',
    9,
    2500000,
    4000000
  UNION ALL 
  SELECT 
    1,
    'price',
    'R$ 4M-20M',
    10,
    4000000,
    20000000
  UNION ALL
  SELECT 
    1,
    'price',
    'Undefined',
    11,
    null,
    null
),
pricing_m2_bins AS (
  SELECT 
    2 AS id_bin,
    'price_m2' AS bin,
    'R$ 0k-3k/m²' AS tag,
    1 AS order,
    0 AS lower_band,
    3000 AS upper_band
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ 3k-4k/m²',
    2,
    3000,
    4000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ 4k-5k/m²',
    3,
    4000,
    5000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ 5k-6k/m²',
    4,
    5000,
    6000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ 6k-7k/m²',
    5,
    6000,
    7000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ 7k-8k/m²',
    6,
    7000,
    8000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ 8k-9k/m²',
    7,
    8000,
    9000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ 9k-12k/m²',
    8,
    9000,
    12000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ 12k-15k/m²',
    9,
    12000,
    15000
  UNION ALL
  SELECT
    2,
    'price_m2',
    'R$ >18k/m²',
    10,
    15000,
    999999999
  UNION ALL
  SELECT 
    2,
    'price_m2',
    'Undefined',
    11,
    null,
    null
),
total_area_bins AS (
  SELECT 
    3 AS id_bin,
    'total_area' AS bin,
    '<=50m²' AS tag,
    1 AS order,
    5 AS lower_band,
    50 AS upper_band
  UNION ALL
  SELECT
    3,
    'total_area',
    '50m²-80m²',
    2,
    50,
    80
  UNION ALL
  SELECT
    3 ,
    'total_area',
    '80m²-120m²',
    3,
    80,
    120
  UNION ALL
  SELECT
    3 ,
    'total_area',
    '>120m²',
    4,
    120,
    999999999
  UNION ALL
  SELECT
    3 ,
    'total_area',
    'Undefined',
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