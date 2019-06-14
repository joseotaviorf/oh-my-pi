WITH qa_listings AS (
  SELECT
    *,
    regexp_extract(trim(house_number), '\d+$') AS extracted_house_number
  FROM datalake_clean.ods_dim_house_listing
  WHERE status = 'publicado' AND is_last_version = 'True'
),
crawled_listings AS (
  SELECT
    *
  FROM
    (
      SELECT
        ws || '-' || id AS id,
        website,
        url,
        crawled_on,
        updated_on,
        business,
        type,
        advertiser_name,
        advertiser_type,
        advertiser_id,
        phones,
        price,
        rent,
        condominium,
        iptu,
        total_area,
        useful_area,
        bedrooms,
        suites,
        toilets,
        garages,
        photos,
        unit_features,
        common_features,
        complementary_info,
        year_building,
        cep,
        lat,
        lng,
        street,
        nb_street,
        neighborhood,
        city,
        state,
        ROW_NUMBER() OVER(PARTITION BY ws || '-' || id ORDER BY DATE(crawled_on) ASC) AS row
      FROM datalake_clean.crawlers
      WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis')
        AND advertiser_name != 'quintoandar'
    ) as tmp
  WHERE
    row = 1  -- get only the first time a listing was posted
    AND DATE(updated_on) >= current_date - interval '7' day
),
qa_listings_unique_locations AS (
  SELECT
    ROUND(CAST(q.house_lng AS DOUBLE), 3) AS qa_lng,
    ROUND(CAST(q.house_lat AS DOUBLE), 3) AS qa_lat,
    q.extracted_house_number AS qa_house_number,
    COUNT(*) AS qa_listings_count,
    ARRAY_AGG(CONCAT(q.house_address, ', ', q.house_number)) AS qa_addresses
  FROM qa_listings q
  WHERE
    COALESCE(q.house_lng, '') NOT IN ('', '0')
    AND COALESCE(q.house_lat, '') NOT IN ('', '0')
    AND COALESCE(q.extracted_house_number, '') NOT IN ('', '0')
  GROUP BY 1, 2, 3
),
crawled_listings_unique_locations AS (
  SELECT
    ROUND(CAST(c.lng AS DOUBLE), 3) AS crawled_lng,
    ROUND(CAST(c.lat AS DOUBLE), 3) AS crawled_lat,
    c.nb_street AS crawled_house_number,
    COUNT(*) AS crawled_listings_count,
    ARRAY_AGG(CONCAT(c.street, c.nb_street)) AS crawled_addresses,
    ARRAY_AGG(c.city) AS crawled_addresses_city
  FROM crawled_listings c
  WHERE
    COALESCE(c.lng, '') NOT IN ('', '0')
    AND COALESCE(c.lat, '') NOT IN ('', '0')
    AND COALESCE(c.nb_street, '') NOT IN ('', '0')
  GROUP BY 1, 2, 3
),
locations_join AS (
  SELECT
    c.crawled_lat,
    c.crawled_lng,
    c.crawled_house_number,
    c.crawled_listings_count,
    c.crawled_addresses,
    c.crawled_addresses_city[1] AS crawled_addresses_city,
    q.qa_lng,
    q.qa_lat,
    q.qa_house_number,
    q.qa_listings_count,
    q.qa_addresses
  FROM crawled_listings_unique_locations c
  FULL OUTER JOIN qa_listings_unique_locations q
    ON c.crawled_lng = q.qa_lng
      AND c.crawled_lat = q.qa_lat
      AND CAST(c.crawled_house_number AS BIGINT) = CAST(q.qa_house_number AS BIGINT)
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
qa_subregions AS (
  SELECT r.sk_region,
         r.name as region_name,
         r.region_code,
         r.city_name,
         r.city_group,
         ST_POLYGON(pr.poligono) as geometry
  FROM datalake_raw.ebdb_poligonoregiao AS pr
  JOIN datalake_clean.ods_dim_region AS r ON r.sk_region = pr.regiao_id
  WHERE r.level = 'SubRegiao'
)
SELECT
  j.*,
  COALESCE(j.crawled_lng, j.qa_lng) AS lng,
  COALESCE(j.crawled_lat, j.qa_lat) AS lat,
  r.sk_region,
  r.region_name AS qa_region_name,
  r.region_code AS qa_region_code,
  r.city_name AS qa_city_name,
  r.city_group AS qa_city_group
FROM locations_join j
LEFT JOIN qa_subregions AS r
  ON ST_WITHIN(ST_POINT(
    COALESCE(j.crawled_lng, j.qa_lng),
    COALESCE(j.crawled_lat, j.qa_lat)
  ), r.geometry)
