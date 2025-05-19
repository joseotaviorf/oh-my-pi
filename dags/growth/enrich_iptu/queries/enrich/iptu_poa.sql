WITH iptu_treatment_address AS (
  SELECT
    id_house,
    'BR' AS address_country_code,
    'RS' AS address_state_code,
    'Porto Alegre' AS address_city,
    NULLIF(INITCAP(address_neighborhood), '') AS address_neighborhood,
    NULLIF(INITCAP(address_street_name), '') AS address_street_name,
    NULLIF(address_number, '') AS address_number,
    NULLIF(address_zipcode, '') AS address_zipcode,
    NULLIF(LOWER(address_complement), '') AS address_complement,
    CAST(NULL AS STRING) AS address_reference,
    CAST(NULL AS DECIMAL(10,7)) AS address_latitude,
    CAST(NULL AS DECIMAL(10,7)) AS address_longitude,
    NULLIF(LOWER(unit_type), '') AS unit_type,
    NULLIF(unit, '') AS address_unit,
    CAST(NULL AS STRING) AS address_building,
    NULLIF(LOWER(property_use_description), '') AS property_use_description,
    NULLIF(LOWER(property_purpose_description), '') AS property_purpose_description,
    floor,
    main_frontage_area_m2,
    CAST(land_area_m2 AS BIGINT) AS land_area_m2,
    CAST(built_area_m2 AS BIGINT) AS built_area_m2,
    taxable_area_m2,
    taxable_land_value,
    taxable_built_value,
    taxable_property_value,
    tax_rate,
    iptu_value,
    tcrs_value,
    TIMESTAMP(dt_load) AS ts_load,
    year
  FROM
    datalake_iptu_poa_clean.iptu_poa
  WHERE
    LOWER(property_use_description) IN (
      'exclusivamente residencial'
    )
    AND LOWER(property_purpose_description) IN (
      'apart-hotel(flat)',
      'apartamento',
      'apartamento de cobertura',
      'residencia condom horiz aberto sem area uso comum',
      'residencia de frente com interiores',
      'residencia de interior',
      'residencia isolada',
      'residencia nao padroniz em condom horizontal fechado',
      'residencia nao padronizada em cond horiz aberto c/ área comum',
      'residencia padronizada cond horiz aberto c/ área uso comum',
      'residencia padronizada em cond horizontal fechado'
    )
    AND year BETWEEN YEAR(DATE('{load_start_date}')) AND YEAR(DATE('{load_end_date}'))
),
house_class AS (
  SELECT
    *,
    CASE
      WHEN (
        property_purpose_description IN (
          'apart-hotel(flat)',
          'apartamento',
          'apartamento de cobertura'
        )
        AND unit_type = 'ap'
      ) THEN 'apartment'
      WHEN (
        property_purpose_description IN (
          'residencia de frente com interiores',
          'residencia de interior',
          'residencia isolada',
          'residencia condom horiz aberto sem area uso comum',
          'residencia nao padroniz em condom horizontal fechado',
          'residencia nao padronizada em cond horiz aberto c/ área comum',
          'residencia padronizada cond horiz aberto c/ área uso comum',
          'residencia padronizada em cond horizontal fechado'
        )
        AND ((unit_type) = 'casa' OR unit_type IS NULL)
      ) THEN 'house'
      ELSE 'unknown'
    END AS house_type
  FROM
    iptu_treatment_address
)
SELECT
  id_house,
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
        unit_type IS NOT NULL
        OR (
          unit_type IS NULL
          AND address_complement NOT RLIKE '\\bcasa\\b'
        )
      )
    ) THEN NULL
    WHEN (
      house_type = 'apartment'
      AND (
        address_complement RLIKE '^[0-9]+$'
        OR address_complement NOT RLIKE '\\b(ap|apart|apartamento|apt|apto|bloc|bloco|torre)\\b'
      )
    ) THEN NULL
    ELSE address_complement
  END AS address_complement,
  address_reference,
  address_latitude,
  address_longitude,
  unit_type,
  address_unit,
  address_building,
  property_use_description,
  property_purpose_description,
  house_type,
  floor,
  main_frontage_area_m2,
  land_area_m2,
  built_area_m2,
  taxable_area_m2,
  taxable_land_value,
  taxable_built_value,
  taxable_property_value,
  tax_rate,
  iptu_value,
  tcrs_value,
  ts_load,
  year
FROM
  house_class
