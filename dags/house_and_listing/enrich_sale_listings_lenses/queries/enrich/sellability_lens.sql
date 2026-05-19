WITH region_cluster_groups AS (
  SELECT
    r.id AS id_region,
    CASE
      WHEN c.cluster_name IS NOT NULL AND c.cluster_name != 'Sem Cluster' THEN c.cluster_name
      WHEN r.city_group IN('RMSP') AND city_name = 'São Paulo' THEN 'São Paulo'
      WHEN r.city_group IN('RMSP') AND city_name != 'São Paulo' THEN 'Grande São Paulo'
      WHEN r.city_group IN('Rio de Janeiro') AND city_name = 'Rio de Janeiro' THEN 'Rio de Janeiro'
      WHEN r.city_group IN('Rio de Janeiro') AND city_name != 'Rio de Janeiro' THEN 'Grande Rio de Janeiro'
      WHEN r.city_group IN('Porto Alegre') AND city_name = 'Porto Alegre' THEN 'Porto Alegre'
      WHEN r.city_group IN('Porto Alegre') AND city_name != 'Porto Alegre' THEN 'Grande Porto Alegre'
      WHEN r.city_group IN('Belo Horizonte') AND city_name = 'Belo Horizonte' THEN 'Belo Horizonte'
      WHEN r.city_group IN('Belo Horizonte') AND city_name != 'Belo Horizonte' THEN 'Grande Belo Horizonte'
      WHEN r.city_group IN('Campinas') AND city_name = 'Campinas' THEN 'Campinas'
      WHEN r.city_group IN('Campinas') AND city_name != 'Campinas' THEN 'Grande Campinas'
      ELSE city_name
    END AS region_group
  FROM
    datalake_region.region AS r
  LEFT JOIN
    datalake_gsheets_clean.for_sale_marketplace_region_clusters AS c
      ON r.id = c.id_region
),
publications AS (
  SELECT
    l.id_house,
    h.id_region,
    'PUBLICATION' AS event,
    h.sale_price AS price,
    TO_DATE(l.ts_first_publication) AS date
  FROM
    datalake_ebdb_clean.listing_business_context AS l
  LEFT JOIN
    datalake_ebdb_listing.house AS h
      ON l.id_house = h.id
  WHERE
    l.business_context = 'SALE'
    AND l.ts_first_publication IS NOT NULL
),
ccvs AS (
  SELECT
    id_house,
    id_region,
    'CCV' AS event,
    sale_price_agreed AS price,
    TO_DATE(ts_sale_agreement_signed) AS date
  FROM
    datalake_sale_offer.sale_offer
  WHERE
    ts_sale_agreement_signed IS NOT NULL
    AND id_house > 0
),
events AS (
  SELECT
    *
  FROM
    publications
  UNION ALL
  SELECT
    *
  FROM
    ccvs
),
events_enriched AS (
  SELECT
    e.id_house,
    e.event,
    rg.region_group,
    h.type AS house_type,
    h.bedrooms,
    COALESCE(p.tag, 'R$ Undefined') AS price_bin,
    COALESCE(pm2.tag, 'R$ Undefined') AS price_m2_bin,
    COALESCE(ta.tag, 'R$ Undefined') AS total_area_bin,
    e.date
  FROM
    events AS e
  LEFT JOIN
    datalake_ebdb_listing.house AS h
      ON h.id = e.id_house
  LEFT JOIN
    datalake_sale_listings_lenses.segmentation_bins AS p
      ON p.bin = 'price'
      AND (e.price >= p.lower_band AND e.price < p.upper_band)
  LEFT JOIN
    datalake_sale_listings_lenses.segmentation_bins AS pm2
      ON pm2.bin = 'price_m2'
      AND ((e.price/h.total_area) >= pm2.lower_band AND (e.price/h.total_area) < pm2.upper_band)
  LEFT JOIN
    datalake_sale_listings_lenses.segmentation_bins AS ta
      ON ta.bin = 'total_area'
      AND (h.total_area >= ta.lower_band AND h.total_area < ta.upper_band)
  LEFT JOIN
    region_cluster_groups AS rg
      ON h.id_region = rg.id_region
),
events_by_day AS (
  SELECT
    date,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin,
    COUNT_IF(event = 'PUBLICATION') AS publications,
    COUNT_IF(event = 'CCV') AS ccvs
  FROM
    events_enriched
  GROUP BY
    1, 2, 3, 4, 5, 6, 7
),
parameters AS (
  SELECT
    date,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin,
    SUM(publications) OVER (PARTITION BY region_group ORDER BY date)/SUM(publications) OVER (PARTITION BY 1 ORDER BY date) AS listings_region_factor,
    SUM(ccvs) OVER (PARTITION BY region_group ORDER BY date)/SUM(ccvs) OVER (PARTITION BY 1 ORDER BY date) AS ccvs_region_factor,
    SUM(publications) OVER (PARTITION BY house_type, region_group ORDER BY date)/SUM(publications) OVER (PARTITION BY region_group ORDER BY date) AS listings_house_type_factor,
    SUM(ccvs) OVER (PARTITION BY house_type, region_group ORDER BY date)/SUM(ccvs) OVER (PARTITION BY region_group ORDER BY date) AS ccvs_house_type_factor,
    SUM(publications) OVER (PARTITION BY bedrooms, region_group ORDER BY date)/SUM(publications) OVER (PARTITION BY region_group ORDER BY date) AS listings_bedroom_factor,
    SUM(ccvs) OVER (PARTITION BY bedrooms, region_group ORDER BY date)/SUM(ccvs) OVER (PARTITION BY region_group ORDER BY date) AS ccvs_bedroom_factor,
    SUM(publications) OVER (PARTITION BY price_bin, region_group ORDER BY date)/SUM(publications) OVER (PARTITION BY region_group ORDER BY date) AS listings_price_factor,
    SUM(ccvs) OVER (PARTITION BY price_bin, region_group ORDER BY date)/SUM(ccvs) OVER (PARTITION BY region_group ORDER BY date) AS ccvs_price_factor,
    SUM(publications) OVER (PARTITION BY total_area_bin, region_group ORDER BY date)/SUM(publications) OVER (PARTITION BY region_group ORDER BY date) AS listings_total_area_factor,
    SUM(ccvs) OVER (PARTITION BY total_area_bin, region_group ORDER BY date)/SUM(ccvs) OVER (PARTITION BY region_group ORDER BY date) AS ccvs_total_area_factor,
    SUM(publications) OVER (PARTITION BY price_m2_bin, region_group ORDER BY date)/SUM(publications) OVER (PARTITION BY region_group ORDER BY date) AS listings_price_m2_factor,
    SUM(ccvs) OVER (PARTITION BY price_m2_bin, region_group ORDER BY date)/SUM(ccvs) OVER (PARTITION BY region_group ORDER BY date) AS ccvs_price_m2_factor
  FROM
    events_by_day
),
factors AS (
  SELECT
    date,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin,
    ROUND(ccvs_region_factor/listings_region_factor, 3) AS region_factor,
    ROUND(ccvs_house_type_factor/listings_house_type_factor, 3) AS house_type_factor,
    ROUND(ccvs_bedroom_factor/listings_bedroom_factor, 3) AS bedrooms_factor,
    ROUND(ccvs_price_factor/listings_price_factor, 3) AS price_factor,
    ROUND(ccvs_total_area_factor/listings_total_area_factor, 3) AS total_area_factor,
    ROUND(ccvs_price_m2_factor/listings_price_m2_factor, 3) AS price_m2_factor
  FROM
    parameters
),
all_combinations AS (
  SELECT
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin
  FROM
    events_enriched
  GROUP BY
    1, 2, 3, 4, 5, 6
),
timeline AS (
  SELECT
    date,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin
  FROM
    datalake_quintoandar.aux_date, all_combinations
  WHERE
    date BETWEEN TO_DATE('2013-01-01', 'yyyy-MM-dd') AND CURRENT_DATE
),
filling_timeline AS (
  SELECT
    date,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin,
    LAST_VALUE(region_factor, TRUE) OVER (PARTITION BY region_group, house_type, bedrooms, price_bin, total_area_bin, price_m2_bin ORDER BY date) AS region_factor,
    LAST_VALUE(house_type_factor, TRUE) OVER (PARTITION BY region_group, house_type, bedrooms, price_bin, total_area_bin, price_m2_bin ORDER BY date) AS house_type_factor,
    LAST_VALUE(bedrooms_factor, TRUE) OVER (PARTITION BY region_group, house_type, bedrooms, price_bin, total_area_bin, price_m2_bin ORDER BY date) AS bedrooms_factor,
    LAST_VALUE(price_factor, TRUE) OVER (PARTITION BY region_group, house_type, bedrooms, price_bin, total_area_bin, price_m2_bin ORDER BY date) AS price_factor,
    LAST_VALUE(total_area_factor, TRUE) OVER (PARTITION BY region_group, house_type, bedrooms, price_bin, total_area_bin, price_m2_bin ORDER BY date) AS total_area_factor,
    LAST_VALUE(price_m2_factor, TRUE) OVER (PARTITION BY region_group, house_type, bedrooms, price_bin, total_area_bin, price_m2_bin ORDER BY date) AS price_m2_factor
  FROM
    timeline
  LEFT JOIN
    factors
      USING(date, region_group, house_type, bedrooms, price_bin, total_area_bin, price_m2_bin)
  QUALIFY
    region_factor IS NOT NULL
    AND house_type_factor IS NOT NULL
    AND bedrooms_factor IS NOT NULL
    AND price_factor IS NOT NULL
    AND total_area_factor IS NOT NULL
    AND price_m2_factor IS NOT NULL
),
sellability_factor AS (
  SELECT
    id_house,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin,
    COALESCE(house_type_factor * bedrooms_factor * price_factor * total_area_factor * price_m2_factor, 0) AS factor,
    filling_timeline.date
  FROM
    events_enriched
  LEFT JOIN
    filling_timeline
      USING(region_group, house_type, bedrooms, price_bin, total_area_bin, price_m2_bin)
  WHERE
    event = 'PUBLICATION'
    AND filling_timeline.date >= events_enriched.date
),
creating_tiers AS (
  SELECT
    id_house,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin,
    factor,
    CASE
      WHEN factor <= 0.3 THEN 'S1'
      WHEN factor > 0.3 AND factor <= 1 THEN 'S2'
      WHEN factor > 1 AND factor <= 2 THEN 'S3'
      WHEN factor > 2 AND factor <= 3 THEN 'S4'
      WHEN factor > 3 THEN 'S5'
    END AS tier,
    date AS ts_tier_started
  FROM
    sellability_factor
),
grouping_tiers AS (
  SELECT
    id_house,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin,
    factor,
    tier,
    ts_tier_started
  FROM
    creating_tiers
  QUALIFY
    tier IS DISTINCT FROM LAG(tier) OVER (PARTITION BY id_house ORDER BY ts_tier_started)
),
tier_status AS (
  SELECT
    id_house,
    region_group,
    house_type,
    bedrooms,
    price_bin,
    total_area_bin,
    price_m2_bin,
    factor,
    tier,
    CASE
      WHEN tier = 'S5' THEN 'Very Similar'
      WHEN tier = 'S4' THEN 'Quite Similar'
      WHEN tier = 'S3' THEN 'Moderately Similar'
      WHEN tier = 'S2' THEN 'Somewhat Similar'
      WHEN tier = 'S1' THEN 'Not Very Similar'
    END AS tier_name,
    ts_tier_started,
    DATE_SUB(LEAD(ts_tier_started) OVER (PARTITION BY id_house ORDER BY ts_tier_started), 1) AS ts_tier_ended
  FROM
    grouping_tiers
)
SELECT
  id_house,
  region_group,
  house_type,
  bedrooms,
  price_bin,
  total_area_bin,
  price_m2_bin,
  factor,
  tier,
  tier_name,
  ts_tier_ended IS NULL AS is_last_tier,
  ts_tier_started,
  ts_tier_ended
FROM
  tier_status
