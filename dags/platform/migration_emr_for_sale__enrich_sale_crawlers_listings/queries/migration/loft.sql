WITH loft_listings_raw AS (
  SELECT
    *,
    CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE) AS ts_updated
  FROM datalake_crawlers_listings_clean.loft
), loft_listings AS (
  SELECT
    id_house,
    id_house_platform,
    platform,
    3p_name,
    unit_type,
    usage_type,
    property_type,
    contract_type,
    business_type,
    neighborhood,
    city,
    state,
    address,
    zip_code,
    st_number,
    lat,
    lng,
    floors,
    num_floors,
    total_area,
    bedrooms,
    suites,
    parking_spaces,
    bathrooms,
    year_built,
    price,
    price_m2,
    installments_price,
    condo_fee,
    iptu,
    is_3p,
    is_marketplace,
    is_platform_property,
    is_last_status,
    ts_created,
    ts_updated,
    ts_last_extraction
  FROM (
    SELECT
      CONCAT(id, 'Loft') AS id_house,
      id AS id_house_platform,
      'Loft' AS platform,
      agency_name AS 3p_name,
      INITCAP(house_info.unit_type) AS unit_type,
      INITCAP(house_info.usage_type[0]) AS usage_type,
      property_type,
      contract_type,
      status AS business_type,
      address.neighborhood AS neighborhood,
      address.city AS city,
      address.state AS state,
      address.street AS address,
      address.zip_code AS zip_code,
      address.number AS st_number,
      geolocation.latitude AS lat,
      geolocation.longitude AS lng,
      house_info.floor AS floors,
      house_info.num_floors AS num_floors,
      house_info.total_area AS total_area,
      house_info.bedrooms AS bedrooms,
      house_info.suites AS suites,
      house_info.parking_spaces AS parking_spaces,
      house_info.bathrooms AS bathrooms,
      house_info.year_built AS year_built,
      CAST(price.sale.price AS DOUBLE) AS price,
      ROUND(CAST(price.sale.price AS DOUBLE) / CAST(house_info.total_area AS INT), 2) AS price_m2,
      installments_price,
      CAST(price.sale.condo_fee AS DOUBLE) AS condo_fee,
      CAST(price.sale.iptu AS DOUBLE) AS iptu,
      has_agency AS is_3p,
      is_marketplace,
      metadata.loft_property AS is_platform_property,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1 AS is_last_status,
      ts_created,
      ts_updated, /* May have a better name */
      FIRST_VALUE(ts_updated) OVER (PARTITION BY 1 ORDER BY ts_updated DESC) AS ts_last_extraction
    FROM loft_listings_raw
  ) AS _t
  WHERE
    is_last_status
), regions AS (
  SELECT
    id_house_platform,
    id_neighborhood,
    neighborhood,
    city_group
  FROM (
    SELECT
      rm.id_house_platform,
      rm.id_neighborhood,
      rm.neighborhood,
      r.city_group,
      ROW_NUMBER() OVER (PARTITION BY id_house_platform ORDER BY dt_updated DESC) AS _w,
      dt_updated
    FROM datalake_crawlers_listings.loft_region_mapping AS rm
    LEFT JOIN datalake_region.region AS r
      ON rm.id_neighborhood = r.id AND r.level IN ('SubRegiao', 'Cidade')
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  l.id_house,
  l.id_house_platform,
  r.id_neighborhood,
  l.platform,
  l.3p_name,
  IF(ts_updated = ts_last_extraction, 'Publicado', 'Despublicado') AS status,
  l.unit_type,
  l.usage_type,
  l.property_type,
  l.contract_type,
  l.business_type,
  l.city,
  r.city_group,
  r.neighborhood,
  l.state,
  l.address,
  l.st_number,
  l.zip_code,
  l.lat,
  l.lng,
  l.floors,
  l.num_floors,
  CAST(NULL AS INT) AS unit_per_floor, /* We don't have this column in Loft, but we put this column in to standardize with Emcasa (it may be unnecessary) */
  l.total_area,
  l.bedrooms,
  l.suites,
  l.parking_spaces,
  l.bathrooms,
  l.year_built,
  l.price,
  l.price_m2,
  l.installments_price,
  l.condo_fee,
  l.iptu,
  CAST(NULL /* Columns referring to the distance CTE present in the old datamart. A solution to check the uniqueness of Loft listings will be developed in another table. */ AS INT) AS nearby_other_platform_houses,
  CAST(NULL AS DOUBLE) AS avg_nearby_price_m2,
  CAST(NULL AS DOUBLE) AS avg_distance,
  CAST(NULL AS BOOLEAN) AS is_exclusive,
  TRUE AS is_for_sale, /* */ /* Standardization columns for other competitors. However, Loft only works with sale. */
  FALSE AS is_for_rent,
  l.is_3p, /* */
  l.is_marketplace,
  l.is_platform_property,
  l.is_last_status,
  l.ts_created,
  l.ts_updated
FROM loft_listings AS l
LEFT JOIN regions AS r
  USING (id_house_platform)
