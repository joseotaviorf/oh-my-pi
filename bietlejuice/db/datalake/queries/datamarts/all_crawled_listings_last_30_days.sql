WITH
-- here we have to scan (almost) all the data first to find the first time a listing was really crawled
-- we limit the columns and then join to listings below to reduce the amount of data scanned
-- we also get the partition from the last 120 days
-- if a listing has been there for longer than 120 days we'll ignore its previous history
crawled_listings_first_time AS (
  SELECT
    id_crawled_listing,
    crawled_on AS first_time_crawled_on,
    updated_on AS first_time_updated_on
  FROM
    (
      SELECT
        ws || '-' || id AS id_crawled_listing,
        crawled_on,
        updated_on,
        ROW_NUMBER() OVER(PARTITION BY ws || '-' || id ORDER BY DATE(crawled_on) ASC) AS row
      FROM datalake_clean.crawlers
      WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis', 'olx')
        AND (advertiser_name is null or advertiser_name != 'quintoandar')
        AND started_on >= CURRENT_DATE - INTERVAL '120' DAY  -- only query listings from crawler jobs started in the last 120 days
    ) as tmp
  WHERE
    row = 1  -- get the first time it was crawled
    AND DATE(updated_on) >= CURRENT_DATE - INTERVAL '30' DAY  -- and only listings posted or updated in the last 30 days
),
crawled_listings AS (
  SELECT
    crawled_listings_first_time.first_time_crawled_on,
    crawled_listings_first_time.first_time_updated_on,
    listings.*
  FROM
    (
      SELECT
        ws || '-' || id AS id_crawled_listing,
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
        cep,
        lat,
        lng,
        street,
        nb_street,
        neighborhood,
        city,
        state,
        photos,
        ROW_NUMBER() OVER(PARTITION BY ws || '-' || id ORDER BY DATE(crawled_on) ASC) AS row
      FROM datalake_clean.crawlers
      WHERE ws IN ('imovelweb', 'vivareal', 'zapimoveis', 'olx')
        AND (advertiser_name is null or advertiser_name != 'quintoandar')  -- ignore our own listings on other sites
        AND started_on >= CURRENT_DATE - INTERVAL '30' DAY  -- only query listings from crawler jobs started in the last 30 days
    ) as listings
  JOIN crawled_listings_first_time ON listings.id_crawled_listing = crawled_listings_first_time.id_crawled_listing
  WHERE
    listings.row = 1  -- get the first time it was crawled within last 120 days
    AND DATE(listings.updated_on) >= CURRENT_DATE - INTERVAL '30' DAY  -- and only listings posted or updated in the last 30 days
)
SELECT
  *
FROM crawled_listings
