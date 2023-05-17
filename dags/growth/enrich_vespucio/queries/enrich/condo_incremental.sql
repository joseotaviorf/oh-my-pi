WITH ebdb_tmp AS (
  SELECT
      condominio.id,
      condominio.name AS condo,
      condominio.address,
      condominio.number,
      condominio.neighborhood,
      condominio.zipcode AS zip_code,
      condominio.city,
      condominio.lat,
      condominio.lng,
      contato.phone_number,
      condominio.construction_year,
      condominio.ts_updated,
      MAX(imovel.has_elevator) AS has_elevator,
      MAX(CASE WHEN imovel.doorman_type == 'horas24' THEN TRUE ELSE FALSE END) AS has_entrance_hall,
      MAX(CASE WHEN iInfo.id_condo_amenities = 1 THEN TRUE ELSE FALSE END) AS has_grill_area,
      MAX(CASE WHEN iInfo.id_condo_amenities = 2 THEN TRUE ELSE FALSE END) AS has_swim_pool,
      MAX(CASE WHEN iInfo.id_condo_amenities = 3 THEN TRUE ELSE FALSE END) AS has_playground,
      MAX(CASE WHEN iInfo.id_condo_amenities = 4 THEN TRUE ELSE FALSE END) AS has_sports_court,
      MAX(CASE WHEN iInfo.id_condo_amenities = 5 THEN TRUE ELSE FALSE END) AS has_gym,
      MAX(CASE WHEN iInfo.id_condo_amenities = 6 THEN TRUE ELSE FALSE END) AS has_party_hall,
      MAX(CASE WHEN iInfo.id_condo_amenities = 7 THEN TRUE ELSE FALSE END) AS has_sauna,
      MAX(CASE WHEN iInfo.id_condo_amenities = 8 THEN TRUE ELSE FALSE END) AS has_laundry,
      MAX(CASE WHEN iInfo.id_condo_amenities = 9 THEN TRUE ELSE FALSE END) AS has_piped_gas,
      MAX(CASE WHEN iInfo.id_condo_amenities = 11 THEN TRUE ELSE FALSE END) AS has_gourmet_area,
      MAX(CASE WHEN iInfo.id_condo_amenities = 12 THEN TRUE ELSE FALSE END) AS has_metro_or_train_close,
      MAX(CASE WHEN iInfo.id_condo_amenities = 13 THEN TRUE ELSE FALSE END) AS has_toy_library
  FROM
      datalake_ebdb_clean.condo condominio
  LEFT JOIN
      datalake_ebdb_clean.house imovel
      ON imovel.id_condo_parent = condominio.id
  LEFT JOIN
      datalake_ebdb_clean.info_condo_amenities iInfo
      ON iInfo.id_house = imovel.id
  LEFT JOIN
      datalake_ebdb_clean.condo_amenities inst
      ON inst.id_condo_amenity = iInfo.id_condo_amenities
  LEFT JOIN
      datalake_ebdb_clean.condo_contact contato
      ON contato.id_condo = condominio.id
  WHERE
      DATE(condominio.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
      AND iInfo.id_condo_amenities IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13)
      AND has_condo_page IS TRUE
      AND condominio.lat IS NOT NULL
      AND condominio.lng IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
)
SELECT
    id,
    'ebdb' AS source,
    condo,
    NULL AS cnpj,
    address,
    number,
    neighborhood,
    zip_code,
    city,
    NULL AS state,
    lat,
    lng,
    phone_number,
    0.5 AS dsr,
    NULL AS type_syndic,
    NULL AS account_type,
    NULL AS type_of_administration,
    NULL AS origin,
    NULL AS total_blocks,
    NULL AS total_ordinances,
    NULL AS total_units,
    NULL AS total_elevators,
    NULL AS number_of_employees,
    NULL AS outsourced_employees,
    NULL AS monthly_tax_revenues,
    NULL AS number_of_garage_parking_slots,
    NULL AS number_of_garage_floors,
    NULL AS number_of_garage_gates,
    NULL AS number_of_water_tanks,
    has_elevator,
    has_entrance_hall,
    has_grill_area,
    has_swim_pool,
    has_sports_court,
    has_gym,
    has_party_hall,
    has_sauna,
    has_laundry,
    has_piped_gas,
    has_gourmet_area,
    has_metro_or_train_close,
    has_toy_library,
    NULL AS has_water_reuse,
    construction_year,
    YEAR(ts_updated) AS updated_year,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    ebdb_tmp

UNION ALL

SELECT
    id,
    'sindiconet' AS source,
    condo,
    cnpj,
    street AS address,
    number,
    neighborhood,
    zip_code,
    city,
    state,
    CAST(lat AS DECIMAL(10,6)) AS lat,
    CAST(lng AS DECIMAL(10,6)) AS lng,
    NULL AS phone_number,
    0.4 AS dsr,
    type_syndic,
    account_type,
    type_of_administration,
    origin,
    total_blocks,
    total_ordinances,
    total_units,
    total_elevators,
    number_of_employees,
    outsourced_employees,
    monthly_tax_revenues,
    number_of_garage_parking_slots,
    number_of_garage_floors,
    number_of_garage_gates,
    number_of_water_tanks,
    has_elevator,
    has_entrance_hall,
    has_grill_area,
    has_swim_pool,
    has_sports_court,
    NULL AS has_gym,
    has_party_hall,
    has_sauna,
    has_laundry,
    has_piped_gas,
    NULL AS has_gourmet_area,
    NULL AS has_metro_or_train_close,
    NULL AS has_toy_library,
    has_water_reuse,
    construction_year,
    YEAR(ts_updated) AS updated_year,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    datalake_sindico_net_clean.condominium
WHERE
    DATE(ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND lat != 'None'
    AND lng != 'None'