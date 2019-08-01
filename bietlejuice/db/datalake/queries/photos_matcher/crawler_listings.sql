WITH
radius AS (
  SELECT 1.0 AS "radius_km"
),
quintoandar_listings AS (
  SELECT
         l.sk_house_listing,
         l.short_id_house,
         l.house_lat,
         l.house_lng,
         l.house_bedrooms,
         regexp_extract(trim(house_number), '\d+$') AS extracted_house_number,
         array_agg(i.nome ORDER BY i.ordem ASC) AS photos
  FROM datalake_clean.ods_dim_house_listing l
  LEFT JOIN datalake_raw.ebdb_imagem i ON l.id_house = i.imovel_id
  WHERE status IN ('publicado') AND is_last_version = 'True'
    AND COALESCE(house_lat, '') != '' AND COALESCE(house_lng, '') != ''
    AND COALESCE(
      regexp_extract(trim(house_number), '\d+$')
      , '') != ''
    AND COALESCE(house_bedrooms, '') != ''
    AND TRY(CAST(l.ts_publication AS TIMESTAMP)) >= CURRENT_DATE - INTERVAL '7' DAY
    -- FIXME: right now we're limiting days, but we will also need to limit for number of matches
    -- meaning, if there's already enough matches then don't bother (or do that in the application? nah, do it here)
  GROUP BY 1, 2, 3, 4, 5, 6
),
first_listings AS (
  SELECT
    id,
    crawled_on AS first_time_crawled_on,
    updated_on AS first_time_updated_on
  FROM
    (
      SELECT
        ws || '-' || id AS id,
        crawled_on,
        updated_on,
        ROW_NUMBER() OVER(PARTITION BY ws || '-' || id ORDER BY DATE(crawled_on) ASC) AS row
      FROM datalake_clean.crawlers
      -- WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis')
      WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis')
        AND advertiser_name != 'quintoandar'
        AND COALESCE(rent, '') != ''
        AND started_on >= CURRENT_DATE - INTERVAL '120' DAY  -- only query listings from crawler jobs started in the last 120 days
    ) as tmp
  WHERE
    row = 1  -- get the first time it was crawled
    AND DATE(updated_on) >= CURRENT_DATE - INTERVAL '1' DAY  -- and only listings posted or updated in the last 2 days
),
crawled_listings AS (
  SELECT
    first_listings.first_time_crawled_on,
    first_listings.first_time_updated_on,
    listings.*
  FROM
    (
      SELECT
        ws || '-' || id AS id,
        -- website,
        -- url,
        -- crawled_on,
        updated_on,
        -- business,
        -- type,
        -- advertiser_name,
        -- advertiser_type,
        -- advertiser_id,
        -- phones,
        -- price,
        -- rent,
        -- condominium,
        -- iptu,
        -- total_area,
        -- useful_area,
        bedrooms,
        -- suites,
        -- toilets,
        -- garages,
        cep,
        lat,
        lng,
        -- street,
        nb_street,
        -- neighborhood,
        -- city,
        -- state,
        photos,
        ROW_NUMBER() OVER(PARTITION BY ws || '-' || id ORDER BY DATE(crawled_on) ASC) AS row
      FROM datalake_clean.crawlers
      -- WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis')
      WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis')
        AND advertiser_name != 'quintoandar'
        AND COALESCE(rent, '') != ''
        AND started_on >= CURRENT_DATE - INTERVAL '1' DAY  -- only query listings from crawler jobs started in the last 2 days
    ) as listings
  JOIN first_listings ON listings.id = first_listings.id
  WHERE
    listings.row = 1  -- get the first time it was crawled within last 30 days
    AND DATE(listings.updated_on) >= CURRENT_DATE - INTERVAL '1' DAY  -- and only listings posted or updated in the last 2 days
),
quintoandar_join_crawled AS
(
  SELECT
    q.sk_house_listing,
    q.short_id_house,
    q.photos AS listing_photos,
    c.id AS crawled_listing_id,
    c.photos AS crawled_photos
  FROM crawled_listings AS c
  JOIN quintoandar_listings AS q
  ON
    (
      ST_DISTANCE(
        ST_POINT(TRY(CAST(q.house_lng AS REAL)), TRY(CAST(q.house_lat AS REAL))),
        ST_POINT(TRY(CAST(c.lng AS REAL)), TRY(CAST(c.lat AS REAL)))
      ) <= ((SELECT radius_km FROM radius) / (111.321 * COS(RADIANS(TRY(CAST(c.lat AS REAL))))))
    )
    AND CAST(q.extracted_house_number AS BIGINT) = CAST(c.nb_street AS BIGINT)
    AND CAST(q.house_bedrooms AS BIGINT) = CAST(c.bedrooms AS BIGINT)
)
SELECT
  ROW_NUMBER () OVER (ORDER BY sk_house_listing) AS row_id,
  sk_house_listing,
  short_id_house,
  listing_photos,
  crawled_listing_id,
  crawled_photos
FROM quintoandar_join_crawled
WHERE COALESCE(crawled_photos, '') != ''
;
