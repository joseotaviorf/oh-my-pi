WITH sao_paulo AS (
  SELECT 
    id_itbi_transaction,
    id_region,
    'ITBI_SP' AS itbi_region,
    address_street_name AS address,
    address_number AS number,
    address_complement AS complement,
    address_reference AS reference,
    address_zipcode AS zipcode,
    address_neighborhood AS neighborhood,
    'São Paulo' AS city,
    'SP' AS state,
    latitude,
    longitude,
    iptu_standard_description AS property_type,
    CASE 
      WHEN raw_source_complement IS NOT NULL AND raw_source_reference IS NOT NULL THEN CONCAT(REPLACE(raw_source_address, '-', ' '), ' ', IFNULL(address_number, ''), ' - ', REPLACE(raw_source_complement, '-', ' '), ' - ', REPLACE(raw_source_reference, '-', ' ')) 
      WHEN raw_source_complement IS NULL AND raw_source_reference IS NOT NULL THEN CONCAT(REPLACE(raw_source_address, '-', ' '), ' ', IFNULL(address_number, ''), ' - ', REPLACE(raw_source_reference, '-', ' '))
      WHEN raw_source_complement IS NOT NULL AND raw_source_reference IS NULL THEN CONCAT(REPLACE(raw_source_address, '-', ' '), ' ', IFNULL(address_number, ''), ' - ', REPLACE(raw_source_complement, '-', ' '))
      WHEN raw_source_complement IS NULL AND raw_source_reference IS NULL THEN CONCAT(REPLACE(raw_source_address, '-', ' '), ' ', IFNULL(address_number, ''))
    END AS raw_source_address,
    source_file,
    land_area_m2,
    built_area_m2,
    ideal_fraction,
    declared_transaction_value,
    adopted_calculation_basis,
    iptu_registration_year AS year_built,
    dt_transaction
  FROM
    datalake_open_external_data.itbi_sp_residential_transactions
),
belo_horizonte AS (
  SELECT 
    id_itbi_transaction,
    id_region,
    'ITBI_BH' AS itbi_region,
    address,
    number,
    complement,
    NULL AS reference,
    zipcode,
    neighborhood,
    city,
    state,
    latitude,
    longitude,
    property_type,
    raw_source_address,
    source_file,
    land_area_m2,
    built_area_m2,
    ideal_fraction,
    NULL AS declared_transaction_value,
    adopted_calculation_basis,
    year_built,
    dt_transaction
  FROM
    datalake_open_external_data.itbi_bh_residential_transactions
)
SELECT 
  *
FROM
  sao_paulo
UNION ALL 
SELECT 
  *
FROM 
  belo_horizonte