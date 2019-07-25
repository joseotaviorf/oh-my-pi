WITH
-- here we have to scan (almost) all the data first to find the first time a listing was really crawled
-- we limit the columns and then join to listings below to reduce the amount of data scanned
-- we also get the partition from the last 120 days
-- if a listing has been there for longer than 120 days we'll ignore its previous history
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
listings AS (
  SELECT
    first_listings.first_time_crawled_on,
    first_listings.first_time_updated_on,
    listings.*
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
        AND COALESCE(rent, '') != ''
        AND started_on >= CURRENT_DATE - INTERVAL '30' DAY  -- only query listings from crawler jobs started in the last 30 days
    ) as listings
  JOIN first_listings ON listings.id = first_listings.id
  WHERE
    listings.row = 1  -- get the first time it was crawled within last 30 days
    AND DATE(listings.updated_on) >= CURRENT_DATE - INTERVAL '30' DAY  -- and only listings posted or updated in the last 30 days
),
doorman AS (
  SELECT
    d.*,
    CASE
      WHEN COALESCE(d.work_place_id, '') != '' AND COALESCE(d.work_house_number, '') != '' THEN d.work_house_number
      ELSE regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')
    END AS extracted_work_house_number,
    CASE
      WHEN COALESCE(d.work_place_id, '') != '' THEN d.work_address
      ELSE trim(regexp_replace(regexp_replace(d.work_address, regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')), '[,;\-\.]')) || ', ' || regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$') || ' ' || d.work_city
    END AS formatted_address,
    COALESCE(a.google_formatted_address, d.work_address) AS google_formatted_address,
    COALESCE(a.lat, d.work_lat) AS lat,
    COALESCE(a.lng, d.work_lng) AS lng,
    u.telefone_principal,
    u.nome,
    u.dadosafiliado_ativo,
    CASE WHEN COALESCE(d.ts_joined_program, '') != '' THEN
      CAST(d.ts_joined_program as timestamp)
    ELSE NULL END AS ts_joined_program_timestamp,
    leads.lead_activity
  FROM datalake_clean.ods_dim_user_doorman d
  LEFT JOIN datalake_raw.doorman_geocoded_addresses a ON d.id_user_doorman = a.id_user_doorman
  JOIN datalake_clean.ods_dim_user u ON CAST(d.sk_user_affiliate AS VARCHAR) = u.dados_afiliado_id
  LEFT JOIN (
      SELECT dim_user_affiliate.sk_user AS sk_user,
             max(DATE(dim_date_lead.date)) AS last_date_lead,
             min(DATE(dim_date_lead.date)) AS first_date_lead,
             CASE
               WHEN max(DATE(dim_date_lead.date)) IS NULL THEN 'no referral'
               WHEN max(DATE(dim_date_lead.date)) >= current_date - interval '30' day THEN 'referral last 30 days'
               WHEN max(DATE(dim_date_lead.date)) >= current_date - interval '90' day AND max(DATE(dim_date_lead.date)) < current_date - interval '30' day THEN 'referral last 90 days'
               WHEN max(DATE(dim_date_lead.date)) >= current_date - interval '180' day AND max(DATE(dim_date_lead.date)) < current_date - interval '90' day THEN 'referral last 180 days'
               ELSE 'referral more than 180 days'
             END as lead_activity
      FROM datalake_clean.ods_fact_house_listing_flows AS fact_house_listing_flows_affiliates
      FULL OUTER JOIN
        (SELECT *
         FROM datalake_clean.ods_dim_user
         WHERE dados_afiliado_id IS NOT NULL) AS dim_user_affiliate ON fact_house_listing_flows_affiliates.sk_user_lead_affiliate = dim_user_affiliate.sk_user
      LEFT JOIN datalake_clean.ods_dim_date AS dim_date_lead ON dim_date_lead.sk_date = fact_house_listing_flows_affiliates.sk_lead_date
      WHERE dim_date_lead.date != '' AND dim_date_lead.date IS NOT NULL
      GROUP BY dim_user_affiliate.sk_user
    ) AS leads
      ON u.sk_user = leads.sk_user
  WHERE
    (
      COALESCE(a.lat, '') != ''
      AND COALESCE(a.lng, '') != ''
      AND COALESCE(
        regexp_extract(regexp_replace(trim(d.work_address), '[,;\-\.]'), '\d+$')
        , '') != ''
    )
    OR COALESCE(d.work_place_id, '') != ''
),
radius AS (
  SELECT 0.1 AS radius_km
),
listings_join_doorman AS
(
  SELECT
    l.id,
    COUNT(*) AS doorman_ct,
    array_agg(telefone_principal) AS doorman_phone,
    array_agg(TRIM(nome)) AS doorman_name,
    array_agg(lead_activity) AS doorman_active,
    array_agg(ts_joined_program) AS doorman_joined_date,
    MAX(ts_joined_program_timestamp) AS latest_doorman_joined_date,
    MIN(ts_joined_program_timestamp) AS earliest_doorman_joined_date
  FROM doorman AS d
  JOIN listings AS l
  ON
    ST_WITHIN(
      ST_POINT(CAST(l.lng AS double), CAST(l.lat AS DOUBLE)),
      ST_BUFFER(
        ST_POINT(CAST(d.lng AS double), CAST(d.lat AS DOUBLE)),
        ((SELECT radius_km FROM radius) / (111.321 * COS(RADIANS(TRY(CAST(d.lat AS REAL))))))  -- distance calculation from decimal degrees to km
      )
    )
    AND CAST(l.nb_street AS BIGINT) = CAST(d.extracted_work_house_number AS BIGINT)
    -- guarantee only 1 bldg match per doorman (nearest?)
  GROUP BY l.id
)
SELECT
  l.id AS listing_id,
  d.doorman_ct,
  d.doorman_phone,
  d.doorman_name,
  d.doorman_active,
  d.doorman_joined_date,
  d.latest_doorman_joined_date,
  d.earliest_doorman_joined_date,
  CASE
    WHEN
      contains(d.doorman_active, 'referral last 30 days') OR
      contains(d.doorman_active, 'referral last 90 days') OR
      contains(d.doorman_active, 'referral last 180 days')
    THEN true
    ELSE false
  END AS has_active_doorman,
  CASE
    WHEN contains(d.doorman_active, 'referral last 30 days') THEN 'referral last 30 days'
    WHEN contains(d.doorman_active, 'referral last 90 days') THEN 'referral last 90 days'
    WHEN contains(d.doorman_active, 'referral last 180 days') THEN 'referral last 180 days'
    WHEN contains(d.doorman_active, 'referral more than 180 days') THEN 'referral more than 180 days'
    ELSE 'no referral'
  END AS most_active_doorman,
  l.website,
  l.url,
  l.crawled_on,
  l.updated_on AS listing_date,
  l.business,
  l.type,
  l.advertiser_name,
  l.advertiser_type,
  l.advertiser_id,
  l.phones,
  l.price,
  l.rent,
  l.condominium,
  l.iptu,
  l.total_area,
  l.useful_area,
  l.bedrooms,
  l.suites,
  l.toilets,
  l.garages,
  l.cep,
  l.lat,
  l.lng,
  l.street,
  l.nb_street,
  l.neighborhood,
  l.city,
  l.state
FROM listings l
LEFT JOIN listings_join_doorman d ON l.id = d.id
