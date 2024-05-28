WITH iptu_enriched AS (
  SELECT
    taxpayer_number,
    condo_number,
    release_notification_number,
    taxpayer_phase,
    street_code,
    'BR' AS address_country,
    'SP' AS address_state,
    'São Paulo' AS address_city,
    INITCAP(neighborhood) AS address_neighborhood,
    INITCAP(address) AS address_street_name,
    CASE
      WHEN number IS NULL THEN 'N/A'
      WHEN CAST(number AS BIGINT) = 99999 THEN 'N/A'
      ELSE CAST(number AS STRING)
    END AS address_number,
    zipcode AS address_zipcode,
    complement AS address_complement,
    INITCAP(reference) AS address_reference,
    property_use_type,
    CASE
      WHEN building_standard_type LIKE "%vertical%" THEN SPLIT(building_standard_type, " - ")[0]
      WHEN building_standard_type LIKE "%horizontal%" THEN SPLIT(building_standard_type, " - ")[0]
      ELSE building_standard_type
    END AS building_standard_type,
    CASE
      WHEN building_standard_type LIKE "%vertical%" THEN INITCAP(SPLIT(building_standard_type, " - ")[1])
      WHEN building_standard_type LIKE "%horizontal%" THEN INITCAP(SPLIT(building_standard_type, " - ")[1])
      ELSE building_standard_type
    END AS building_standard_type_tier,
    IF(land_type = "Lote de esquina em ZER", "Lote de esquina em zero", land_type) AS land_type,
    land_area_m2,
    built_area_m2,
    occupied_area_m2,
    land_price_m2,
    building_price_m2,
    frontage,
    ideal_fraction,
    depreciation_factor,
    qty_street_corners_or_fronts,
    qty_floors,
    NULLIF(built_year, 0) AS built_year,
    iptu_year,
    first_year_of_taxpayer_life,
    first_month_of_taxpayer_life,
    TIMESTAMP(dt_registration) AS ts_registration,
    TIMESTAMP(dt_load) AS ts_load
  FROM
    datalake_iptu_clean.iptu_sp
  WHERE
    (building_standard_type LIKE "Comercial horizontal%" AND property_use_type IN ("Residência", "Residência coletiva, exclusive cortiço (mais de uma residência no lote)", "Residência e outro uso (predominância residencial)"))
    OR (building_standard_type LIKE "Comercial vertical%" AND property_use_type IN ("Flat de uso comercial (semelhante a hotel)", "Flat residencial em condomínio",  "Residência", "Residência e outro uso (predominância residencial)"))
    OR (building_standard_type LIKE "Residencial horizontal%" AND property_use_type IN ("Apartamento em condomínio", "Residência", "Residência coletiva, exclusive cortiço (mais de uma residência no lote)", "Residência e outro uso (predominância residencial)"))
    OR (building_standard_type LIKE "Residencial horizontal%" AND property_use_type IN ("Apartamento em condomínio", "Flat de uso comercial (semelhante a hotel)", "Flat residencial em condomínio", "Residência", "Residência coletiva, exclusive cortiço (mais de uma residência no lote)", "Residência e outro uso (predominância residencial)"))
)
SELECT
  i.taxpayer_number,
  i.condo_number,
  i.release_notification_number,
  i.taxpayer_phase,
  i.street_code,
  i.address_street_name,
  i.address_number,
  i.address_zipcode,
  i.address_complement,
  i.address_reference,
  i.address_neighborhood,
  i.address_state,
  i.address_city,
  i.address_country,
  i.property_use_type,
  i.building_standard_type,
  i.building_standard_type_tier,
  i.land_type,
  i.land_area_m2,
  i.built_area_m2,
  i.occupied_area_m2,
  i.land_price_m2,
  i.building_price_m2,
  i.frontage,
  i.ideal_fraction,
  i.depreciation_factor,
  i.qty_street_corners_or_fronts,
  i.qty_floors,
  i.built_year,
  i.iptu_year,
  i.first_year_of_taxpayer_life,
  i.first_month_of_taxpayer_life,
  i.ts_registration,
  i.ts_load
FROM
  iptu_enriched AS i
