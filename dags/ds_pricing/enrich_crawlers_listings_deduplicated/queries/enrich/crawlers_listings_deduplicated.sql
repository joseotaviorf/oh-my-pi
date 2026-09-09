WITH loft_listings AS (
  SELECT DISTINCT
    id_house,
    LOWER(platform) AS platform,
    state,
    city,
    address AS street,
    st_number AS street_number,
    CAST(lat AS FLOAT) AS latitude,
    CAST(lng AS FLOAT) AS longitude,
    CAST(total_area AS FLOAT) AS total_area,
    price,
    price_m2,
    ts_created,
    ts_updated
  FROM
    datalake_crawlers_listings.loft
  WHERE
    business_type = 'FOR_SALE'
    AND (price_m2 BETWEEN 1000 AND 100000)
    AND price_m2 IS NOT NULL
),
zap_listings AS (
  SELECT DISTINCT
    id_house,
    LOWER(platform) AS platform,
    state,
    address_city AS city,
    street,
    street_number,
    CAST(latitude AS FLOAT) AS latitude,
    CAST(longitude AS FLOAT) AS longitude,
    total_area,
    price_sale AS price,
    price_m2_sale AS price_m2,
    ts_created,
    ts_updated
  FROM
    datalake_crawler_zap_imoveis.zap_imoveis
  WHERE
    price_m2_sale IS NOT NULL
    AND (price_m2_sale BETWEEN 1000 AND 100000)
    AND latitude IS NOT NULL
    AND street_number IS NOT NULL
    AND street IS NOT NULL
    AND neighborhood IS NOT NULL
    AND usage_type = 'RESIDENTIAL'
),
crawlers_listings AS (
  SELECT
    id_house,
    platform,
    state,
    city,
    street,
    street_number,
    latitude,
    longitude,
    total_area,
    price,
    price_m2,
    ts_created,
    ts_updated
  FROM
    loft_listings
  UNION ALL
  SELECT
    id_house,
    platform,
    state,
    city,
    street,
    street_number,
    latitude,
    longitude,
    total_area,
    price,
    price_m2,
    ts_created,
    ts_updated
  FROM
    zap_listings
),
listings_deduplicated AS (
  SELECT
    id_house,
    platform,
    state,
    city,
    street,
    street_number,
    latitude,
    longitude,
    total_area,
    price,
    price_m2,
    ts_created,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY latitude, longitude, price_m2 ORDER BY ts_created ASC) AS row_number,
    MAX(ts_updated) OVER (PARTITION BY latitude, longitude, price_m2) AS max_ts_updated,
    MIN(ts_created) OVER (PARTITION BY latitude, longitude, price_m2) AS min_ts_created,
    REPLACE(REPLACE(LOWER(city), '_', ' '), '-', ' ') AS clean_city
  FROM
    crawlers_listings
)
SELECT
  id_house,
  platform,
  state,
  city,
  street,
  street_number,
  latitude,
  longitude,
  total_area,
  price,
  price_m2,
  ts_created,
  ts_updated,
  row_number,
  max_ts_updated,
  min_ts_created,
  clean_city
FROM
  listings_deduplicated
WHERE
  row_number = 1
