WITH address_extraction AS (
  SELECT
    id_house,
    NULLIF(address, '') AS address,
    'BR' AS address_country_code,
    'MG' AS address_state_code,
    'Belo Horizonte' AS address_city,
    -- Extract neighborhood (after the last ' - ')
    NULLIF(INITCAP(REGEXP_EXTRACT(address, r'- ([^-]+)$')), '') AS address_neighborhood,
    -- Extract street name (before comma)
    NULLIF(INITCAP(REGEXP_EXTRACT(address, r'^(.*?),')), '') AS address_street_name,
    -- Extract street number (number after comma)
    NULLIF(REGEXP_EXTRACT(address, r',\s*(\d+)'), '') AS address_number,
    CAST(NULL AS STRING) AS address_zipcode,
    -- Extract complement (everything between the first ' - ' and the last ' - ')
    NULLIF(LOWER(TRIM(REGEXP_EXTRACT(address, r'-\s+(.*)\s+-'))), '') AS address_complement,
    CAST(NULL AS STRING) AS address_reference,
    CAST(NULL AS DECIMAL(10,7)) AS address_latitude,
    CAST(NULL AS DECIMAL(10,7)) AS address_longitude,
    LOWER(property_use_description) AS property_use_description,
    LOWER(property_purpose_description) AS property_purpose_description,
    CAST(land_area_m2 AS BIGINT) AS land_area_m2,
    CAST(built_area_m2 AS BIGINT) AS built_area_m2,
    land_value_m2,
    built_value_m2,
    ideal_land_fraction_m2,
    ideal_land_fraction,
    taxable_land_value,
    taxable_built_value,
    taxable_property_value,
    transport_fee_value,
    fire_fee_value,
    street_lighting_fee_value,
    special_discount,
    iptu_value,
    tcrs_value,
    construction_year,
    TIMESTAMP(dt_load) AS ts_load,
    year
  FROM
    datalake_iptu_bh_clean.iptu_bh
  WHERE
    LOWER(property_use_description) = 'proprio'
    AND LOWER(property_purpose_description) = 'comum'
    AND address IS NOT NULL
    AND LOWER(iptu_status) = 'ativo'
    AND year BETWEEN YEAR(DATE('{load_start_date}')) AND YEAR(DATE('{load_end_date}'))
),
complement_class AS (
  SELECT
    *,
    CASE
      WHEN address_complement RLIKE '\\bcomercial\\b' THEN 'commercial'
      WHEN address_complement RLIKE '\\bgarage\\b' THEN 'garage'
      WHEN (address_complement RLIKE '\\b(loja|slj)\\b') THEN 'store'
      WHEN address_complement RLIKE '\\bbox\\b' THEN 'box'
      WHEN (
        address_complement RLIKE '\\bcasa\\b'
        OR address_complement = LOWER(address_neighborhood)
        OR LEN(address_complement) = 1
        OR address_complement IS NULL
      ) THEN 'house'
      WHEN address_complement RLIKE '\\b(apt|ap|apto)\\b' THEN 'apartment'
      WHEN address_complement RLIKE '\\bandar\\b' THEN 'floor'
      WHEN address_complement RLIKE '\\bsala\\b' THEN 'room'
      WHEN address_complement RLIKE '\\bquadra\\b' THEN 'block'
      WHEN address_complement RLIKE '\\bconj\\b' THEN 'suite'
      WHEN address_complement RLIKE '\\bpavmto\\b' THEN 'floor level'
      WHEN address_complement RLIKE '\\bsubsl\\b' THEN 'basement'
      ELSE 'unknown'
    END AS house_type
  FROM
    address_extraction
  WHERE
    address_street_name IS NOT NULL
    AND address_number IS NOT NULL
    AND address_neighborhood IS NOT NULL
)
SELECT
  id_house,
  address,
  address_country_code,
  address_state_code,
  address_city,
  address_neighborhood,
  address_street_name,
  address_number,
  address_zipcode,
  CASE
    WHEN (
      house_type = 'house'
      AND (
        address_complement = LOWER(address_neighborhood)
        OR LEN(address_complement) = 1
      )
    ) THEN NULL
    ELSE address_complement
  END AS address_complement,
  address_reference,
  address_latitude,
  address_longitude,
  CAST(NULL AS STRING) AS address_unit,
  CAST(NULL AS STRING) AS address_building,
  property_use_description,
  property_purpose_description,
  house_type,
  land_area_m2,
  built_area_m2,
  land_value_m2,
  built_value_m2,
  ideal_land_fraction_m2,
  ideal_land_fraction,
  taxable_land_value,
  taxable_built_value,
  taxable_property_value,
  transport_fee_value,
  fire_fee_value,
  street_lighting_fee_value,
  special_discount,
  iptu_value,
  tcrs_value,
  construction_year,
  ts_load,
  year
FROM
  complement_class
