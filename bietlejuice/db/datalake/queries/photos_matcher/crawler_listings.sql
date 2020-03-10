WITH
radius AS (
  SELECT 1.0 AS "radius_km"
),
images AS (
  SELECT
    i.id_house,
    i.name
  FROM datalake_ebdb_clean_prod.image i
  WHERE i.sequence <= 40  -- no more than 40 images per listing
    AND NOT regexp_like(LOWER(i.subtitle), 'churrasqueira|comum|condominio|condomínio|externa|externo|festa|festas|futebol|garagem|gourmet|jardim|piscina|playground|quadra|quintal|salão|sauna|skate|social|spa|subsolo')
    -- remove photos from external areas which will not help identify the apartment interior
  ORDER BY i.id_house, i.sequence ASC
),
matches AS (
  SELECT
    m.sk_house_listing,
    m.id_crawled_listing,
    COUNT(*) AS total_matches
  FROM datalake_raw.crawler_matches m
  GROUP BY 1, 2
),
quintoandar_listings AS (
  SELECT
         l.sk_house_listing,
         l.short_id_house,
         l.house_lat,
         l.house_lng,
         l.house_bedrooms,
         regexp_extract(trim(house_number), '\d+$') AS extracted_house_number,
         array_agg(i.name) AS photos
  FROM datalake_clean.ods_dim_house_listing l
  LEFT JOIN images i ON cast(l.id_house as bigint) = i.id_house
  WHERE status IN ('publicado') AND is_last_version = 'True'
    AND COALESCE(house_lat, '') != '' AND COALESCE(house_lng, '') != ''
    AND COALESCE(
      regexp_extract(trim(house_number), '\d+$')
      , '') != ''
    AND COALESCE(house_bedrooms, '') != ''
    AND TRY(CAST(l.ts_publication AS TIMESTAMP)) >= CURRENT_DATE - INTERVAL '1' DAY -- our listings pulished in the last 1 day
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
      WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis')
        AND advertiser_name != 'quintoandar'
        AND COALESCE(rent, '') != ''
        AND started_on >= CURRENT_DATE - INTERVAL '120' DAY  -- only query listings from crawler jobs started in the last 120 days
    ) as tmp
  WHERE
    row = 1  -- get the first time it was crawled
    AND DATE(updated_on) >= CURRENT_DATE - INTERVAL '30' DAY  -- and only listings posted or updated in the last 30 days
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
        updated_on,
        bedrooms,
        cep,
        lat,
        lng,
        nb_street,
        photos,
        ROW_NUMBER() OVER(PARTITION BY ws || '-' || id ORDER BY DATE(crawled_on) ASC) AS row,
        ROW_NUMBER() OVER(PARTITION BY description, website, advertiser_id, price) AS ad_deduplication_row
      FROM datalake_clean.crawlers
      WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis')
        AND advertiser_name != 'quintoandar'
        AND COALESCE(rent, '') != ''
        AND COALESCE(nb_street, '') != ''
        AND COALESCE(lat, '') != ''
        AND COALESCE(lng, '') != ''
        AND COALESCE(bedrooms, '') != ''
        AND started_on >= CURRENT_DATE - INTERVAL '30' DAY  -- only query listings from crawler jobs started in the last 30 days
        AND COALESCE(photos, '') != ''
        AND cardinality(split(photos, ',')) > 4  -- crawled listing must have at least 4 photos
    ) as listings
  JOIN first_listings ON listings.id = first_listings.id
  WHERE
    listings.row = 1  -- get the first time it was crawled within last 120 days
    AND DATE(listings.updated_on) >= CURRENT_DATE - INTERVAL '30' DAY  -- and only listings posted or updated in the last 30 days
    AND listings.ad_deduplication_row = 1  -- we employ this heuristic to try to deduplicate listings even if they have different ids
),
quintoandar_join_crawled AS
(
  SELECT
    q.sk_house_listing,
    q.short_id_house,
    q.photos AS listing_photos,
    c.id AS id_crawled_listing,
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
    AND TRY(CAST(q.extracted_house_number AS BIGINT)) = TRY(CAST(c.nb_street AS BIGINT))
    AND TRY(CAST(q.house_bedrooms AS BIGINT)) = TRY(CAST(c.bedrooms AS BIGINT))
)
SELECT
  ROW_NUMBER () OVER (ORDER BY c.sk_house_listing) AS row_id,
  c.sk_house_listing,
  c.short_id_house,
  c.listing_photos,
  c.id_crawled_listing,
  c.crawled_photos,
  CURRENT_DATE AS dt_created
FROM quintoandar_join_crawled c
LEFT JOIN matches m ON c.sk_house_listing = m.sk_house_listing AND c.id_crawled_listing = m.id_crawled_listing
WHERE COALESCE(m.total_matches, 0) <= 3  -- we don't want to consider listings + crawler listings combinations that have had more than 3 matches already
;
