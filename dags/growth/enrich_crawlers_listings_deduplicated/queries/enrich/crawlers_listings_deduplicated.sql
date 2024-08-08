WITH loft_listings AS(
  SELECT DISTINCT
    id_house,
    ts_created,
    ts_updated,
    platform,
    state,
    city,
    address AS street,
    st_number AS street_number,
    CAST(lat AS FLOAT) AS latitude,
    CAST(lng AS FLOAT) AS longitude,
    CAST(total_area AS FLOAT) AS total_area,
    price,
    price_m2
  FROM datalake_crawlers_listings.loft
  WHERE business_type = 'FOR_SALE'
    AND price_m2 > 1000
    AND price_m2 < 100000
    AND price_m2 IS NOT NULL
),
zap_listings AS (
  SELECT DISTINCT
    id_house,
    ts_created, 
    ts_updated, 
    platform, 
    state, 
    city, 
    street, 
    street_number, 
    CAST(latitude AS FLOAT) AS latitude, 
    CAST(longitude AS FLOAT) AS longitude, 
    total_area, 
    price_sale AS price, 
    price_m2_sale AS price_m2
  FROM
    datalake_crawlers_listings.zap_imoveis
  WHERE
    price_m2_sale IS NOT NULL
    AND price_m2_sale > 1000
    AND price_m2_sale < 100000
    AND latitude IS NOT NULL
    AND street_number IS NOT NULL
),
vivareal_listings AS (
  SELECT DISTINCT
    id_house, 
    ts_created, 
    ts_updated, 
    platform, 
    state, 
    city, 
    street, 
    street_number, 
    CAST(latitude AS FLOAT) AS latitude, 
    CAST(longitude AS FLOAT) AS longitude, 
    total_area, 
    price_sale AS price, 
    price_m2_sale AS price_m2
  FROM datalake_crawlers_listings.viva_real
  WHERE
    price_m2_sale IS NOT NULL
    AND price_m2_sale > 1000
    AND price_m2_sale < 100000
    AND latitude IS NOT NULL
    AND street_number IS NOT NULL
),
emcasa_listings AS (
  SELECT DISTINCT
    id_house, 
    ts_updated AS ts_created, 
    ts_updated, 
    platform, 
    state, 
    city, 
    address AS street, 
    st_number AS street_number, 
    CAST(lat AS FLOAT) AS latitude, 
    CAST(lng AS FLOAT) AS longitude, 
    total_area, 
    price, 
    price_m2
  FROM datalake_crawlers_listings.em_casa
  WHERE
    price_m2 IS NOT NULL
    AND price_m2 > 1000
    AND price_m2 < 100000
    AND lat IS NOT NULL
),
crawlers_listings AS (
  SELECT
    * 
  FROM (
    SELECT * FROM loft_listings
    UNION ALL
    SELECT * FROM zap_listings
    UNION ALL
    SELECT * FROM vivareal_listings
    UNION ALL
    SELECT * FROM emcasa_listings
  ) AS combined_listings
),
listings_deduplicated AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY latitude, longitude, price_m2 ORDER BY ts_created ASC) AS row_number,
    MAX(ts_updated) OVER (PARTITION BY latitude, longitude, price_m2) AS max_ts_updated,
    MIN(ts_created) OVER (PARTITION BY latitude, longitude, price_m2) AS min_ts_created,
    REPLACE(REPLACE(LOWER(city), '_', ' '), '-', ' ') AS clean_city
  FROM crawlers_listings
)

SELECT 
  * 
FROM 
  listings_deduplicated
WHERE row_number = 1