WITH dim_region AS (
  SELECT
    sk_region,
    TRIM(name) AS neighborhood,
    city_group,
    city_name,
    short_region_name
  FROM
    dw_public.dim_region
  WHERE
    country_code = 'BR'
),
active_for_rent_city_groups AS (
  SELECT
    r.city_group,
    COUNT(DISTINCT id_house) AS listings_publisheds
  FROM
    dw_rent.fact_house_listings AS f
  INNER JOIN
    dw_rent.dim_house_listing AS d
      USING(sk_house_listing)
  INNER JOIN
    dw_public.dim_region AS r
      USING(sk_region)
  WHERE
    d.status = 'PUBLISHED'
    AND r.country_code = 'BR'
  GROUP BY 1
),
all_transactions AS (
  SELECT
    id_house,
    sk_region,
    hl.house_rent / NULLIF(hl.house_total_area, 0) AS price_per_m2,
    DATE(DATE_TRUNC('quarter', dc.ts_signature)) AS dt_quarter
  FROM
    dw_rent.dim_house_listing AS hl
  INNER JOIN
    dw_rent.fact_house_listings AS fhl
      USING(sk_house_listing)
  INNER JOIN
    dw_rent.dim_contract AS dc
      USING(sk_contract)
  INNER JOIN
    dim_region AS r
      USING(sk_region)
  INNER JOIN
    active_for_rent_city_groups AS c
      USING(city_group)
  WHERE
    sk_contract IS NOT NULL
    AND hl.house_rent BETWEEN 500 AND 20000
    AND c.listings_publisheds > 100
),
median_price_by_region AS (
  SELECT
    sk_region,
    dt_quarter,
    CAST(MEDIAN(price_per_m2) AS BIGINT) AS median_price_per_m2
  FROM
    all_transactions
  WHERE
    price_per_m2 < 50000
    AND dt_quarter >= DATE('2019-01-01')
  GROUP BY 1, 2
),
price_published AS (
  SELECT
    NOW() AS ts_event,
    CAST(DATE_FORMAT(CAST(dt_quarter AS DATE), 'yyyy-MM-dd') AS STRING) AS dt_quarter,
    CAST(sk_region AS BIGINT) AS id_region,
    CAST(CONCAT(neighborhood, '/', city_name, '/', short_region_name) AS STRING) AS region_name,
    ROUND(CAST(median_price_per_m2 AS FLOAT),2) AS median_price_per_m2
  FROM
    median_price_by_region AS p
  INNER JOIN
    dim_region AS r
      USING(sk_region)
  WHERE
    sk_region != -1
    AND p.dt_quarter + INTERVAL '2' month <= DATE_TRUNC('MONTH', CURRENT_DATE)
)
SELECT
  DATE_FORMAT(ts_event, 'yyyy-MM-dd\'T\'HH:mm:ss') AS ts_event,
  MONOTONICALLY_INCREASING_ID() AS id,
  dt_quarter,
  id_region,
  region_name,
  median_price_per_m2
FROM
  price_published
