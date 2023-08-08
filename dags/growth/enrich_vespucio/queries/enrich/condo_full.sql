WITH
importance_order AS (
  SELECT 'Condominio' AS type, 1 AS order
  UNION ALL
  SELECT 'Administradora' AS type, 2 AS order
  UNION ALL
  SELECT 'Porteiro' AS type, 3 AS order
  UNION ALL
  SELECT 'Sindico' AS type, 4 AS order
  UNION ALL
  SELECT 'Zelador' AS type, 5 AS order
),
phones_mode AS (
  SELECT
    cc.id_condo,
    cc.type,
    o.order,
    MODE(cc.phone_number) AS phone_number
  FROM
    datalake_ebdb_clean.condo_contact cc
    JOIN importance_order o
      ON cc.type = o.type
  GROUP BY 1,2,3
  ORDER BY order
),
phones_set AS (
  SELECT
    id_condo,
    ARRAY_AGG(phone_number) phone_array
  FROM 
    phones_mode
  GROUP BY 1
),
condo_ebdb AS (
  SELECT
    c.id,
    c.name AS condo,
    c.address,
    c.number,
    c.neighborhood,
    c.zipcode AS zip_code,
    c.city,
    c.lat,
    c.lng,
    c.code,
    COALESCE(ps.phone_array[0],ps.phone_array[1],ps.phone_array[2],ps.phone_array[3],ps.phone_array[4]) AS phone_number,
    c.has_condo_page,
    c.construction_year,
    c.ts_updated
  FROM
    datalake_ebdb_clean.condo c
    LEFT JOIN phones_set ps
      ON ps.id_condo = c.id
  WHERE
    c.lat IS NOT NULL
    AND c.lng IS NOT NULL
),
condo_amenities AS (
  SELECT
    condo_ebdb.id,
    h.id AS id_house,
    h.has_elevator AS has_elevator,
    CASE 
      WHEN h.doorman_type = 'horas24' THEN TRUE
      WHEN h.doorman_type IS NULL THEN NULL
      ELSE FALSE
    END AS has_entrance_hall,
    CASE WHEN ica.id_condo_amenities = 1 THEN has_characteristic END AS has_playground,
    CASE WHEN ica.id_condo_amenities = 2 THEN has_characteristic END AS has_swim_pool,
    CASE WHEN ica.id_condo_amenities = 3 THEN has_characteristic END AS has_grill_area,
    CASE WHEN ica.id_condo_amenities = 4 THEN has_characteristic END AS has_sports_court,
    CASE WHEN ica.id_condo_amenities = 5 THEN has_characteristic END AS has_gym,
    CASE WHEN ica.id_condo_amenities = 6 THEN has_characteristic END AS has_party_hall,
    CASE WHEN ica.id_condo_amenities = 7 THEN has_characteristic END AS has_sauna,
    CASE WHEN ica.id_condo_amenities = 8 THEN has_characteristic END AS has_laundry,
    CASE WHEN ica.id_condo_amenities = 9 THEN has_characteristic END AS has_piped_gas,
    CASE WHEN ica.id_condo_amenities = 11 THEN has_characteristic END AS has_gourmet_area,
    CASE WHEN ica.id_condo_amenities = 12 THEN has_characteristic END AS has_metro_or_train_close,
    CASE WHEN ica.id_condo_amenities = 13 THEN has_characteristic END AS has_toy_library,
    condo_ebdb.has_condo_page
  FROM
    condo_ebdb
    LEFT JOIN datalake_ebdb_clean.house AS h
      ON h.id_condo_parent = condo_ebdb.id
    LEFT JOIN datalake_ebdb_clean.info_condo_amenities ica
      ON ica.id_house = h.id
),
amenities_cnt AS (
  SELECT
    id,
    COUNT(DISTINCT CASE WHEN has_condo_page THEN id_house ELSE NULL END) AS has_condo_page_true,
    COUNT(DISTINCT CASE WHEN has_elevator THEN id_house ELSE NULL END) AS has_elevator_true,
    COUNT(DISTINCT CASE WHEN has_entrance_hall THEN id_house ELSE NULL END) AS has_entrance_hall_true,
    COUNT(DISTINCT CASE WHEN has_grill_area THEN id_house ELSE NULL END) AS has_grill_area_true,
    COUNT(DISTINCT CASE WHEN has_swim_pool THEN id_house ELSE NULL END) AS has_swim_pool_true,
    COUNT(DISTINCT CASE WHEN has_sports_court THEN id_house ELSE NULL END) AS has_sports_court_true,
    COUNT(DISTINCT CASE WHEN has_gym THEN id_house ELSE NULL END) AS has_gym_true,
    COUNT(DISTINCT CASE WHEN has_party_hall THEN id_house ELSE NULL END) AS has_party_hall_true,
    COUNT(DISTINCT CASE WHEN has_sauna THEN id_house ELSE NULL END) AS has_sauna_true,
    COUNT(DISTINCT CASE WHEN has_laundry THEN id_house ELSE NULL END) AS has_laundry_true,
    COUNT(DISTINCT CASE WHEN has_piped_gas THEN id_house ELSE NULL END) AS has_piped_gas_true,
    COUNT(DISTINCT CASE WHEN has_gourmet_area THEN id_house ELSE NULL END) AS has_gourmet_area_true,
    COUNT(DISTINCT CASE WHEN has_metro_or_train_close THEN id_house ELSE NULL END) AS has_metro_or_train_close_true,
    COUNT(DISTINCT CASE WHEN has_toy_library THEN id_house ELSE NULL END) AS has_toy_library_true,
    COUNT(DISTINCT CASE WHEN has_condo_page = FALSE THEN id_house ELSE NULL END) AS has_condo_page_false,
    COUNT(DISTINCT CASE WHEN has_elevator = FALSE THEN id_house ELSE NULL END) AS has_elevator_false,
    COUNT(DISTINCT CASE WHEN has_entrance_hall = FALSE THEN id_house ELSE NULL END) AS has_entrance_hall_false,
    COUNT(DISTINCT CASE WHEN has_grill_area = FALSE THEN id_house ELSE NULL END) AS has_grill_area_false,
    COUNT(DISTINCT CASE WHEN has_swim_pool = FALSE THEN id_house ELSE NULL END) AS has_swim_pool_false,
    COUNT(DISTINCT CASE WHEN has_sports_court = FALSE THEN id_house ELSE NULL END) AS has_sports_court_false,
    COUNT(DISTINCT CASE WHEN has_gym = FALSE THEN id_house ELSE NULL END) AS has_gym_false,
    COUNT(DISTINCT CASE WHEN has_party_hall = FALSE THEN id_house ELSE NULL END) AS has_party_hall_false,
    COUNT(DISTINCT CASE WHEN has_sauna = FALSE THEN id_house ELSE NULL END) AS has_sauna_false,
    COUNT(DISTINCT CASE WHEN has_laundry = FALSE THEN id_house ELSE NULL END) AS has_laundry_false,
    COUNT(DISTINCT CASE WHEN has_piped_gas = FALSE THEN id_house ELSE NULL END) AS has_piped_gas_false,
    COUNT(DISTINCT CASE WHEN has_gourmet_area = FALSE THEN id_house ELSE NULL END) AS has_gourmet_area_false,
    COUNT(DISTINCT CASE WHEN has_metro_or_train_close = FALSE THEN id_house ELSE NULL END) AS has_metro_or_train_close_false,
    COUNT(DISTINCT CASE WHEN has_toy_library = FALSE THEN id_house ELSE NULL END) AS has_toy_library_false
  FROM
    condo_amenities
  GROUP BY 1
),
base AS (
    SELECT
    condo_ebdb.id,
    'ebdb' AS source,
    condo_ebdb.condo,
    NULL AS cnpj,
    condo_ebdb.address,
    condo_ebdb.number,
    condo_ebdb.neighborhood,
    condo_ebdb.zip_code,
    condo_ebdb.city,
    NULL AS state,
    condo_ebdb.lat,
    condo_ebdb.lng,
    condo_ebdb.code,
    condo_ebdb.phone_number,
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
    CASE 
        WHEN amenities_cnt.has_condo_page_true = 0 AND amenities_cnt.has_condo_page_false = 0 THEN NULL
        WHEN amenities_cnt.has_condo_page_true >= amenities_cnt.has_condo_page_false THEN TRUE
        WHEN amenities_cnt.has_condo_page_true < amenities_cnt.has_condo_page_false THEN FALSE 
    END AS has_condo_page,
    CASE 
        WHEN amenities_cnt.has_elevator_true = 0 AND amenities_cnt.has_elevator_false = 0 THEN NULL
        WHEN amenities_cnt.has_elevator_true >= amenities_cnt.has_elevator_false THEN TRUE
        WHEN amenities_cnt.has_elevator_true < amenities_cnt.has_elevator_false THEN FALSE
    END AS has_elevator,
    CASE 
        WHEN amenities_cnt.has_entrance_hall_true = 0 AND amenities_cnt.has_entrance_hall_false = 0 THEN NULL
        WHEN amenities_cnt.has_entrance_hall_true >= amenities_cnt.has_entrance_hall_false THEN TRUE
        WHEN amenities_cnt.has_entrance_hall_true < amenities_cnt.has_entrance_hall_false THEN FALSE
    END AS has_entrance_hall,
    CASE 
        WHEN amenities_cnt.has_grill_area_true = 0 AND amenities_cnt.has_grill_area_false = 0 THEN NULL
        WHEN amenities_cnt.has_grill_area_true >= amenities_cnt.has_grill_area_false THEN TRUE
        WHEN amenities_cnt.has_grill_area_true < amenities_cnt.has_grill_area_false THEN FALSE
    END AS has_grill_area,
    CASE 
        WHEN amenities_cnt.has_swim_pool_true = 0 AND amenities_cnt.has_swim_pool_false = 0 THEN NULL
        WHEN amenities_cnt.has_swim_pool_true >= amenities_cnt.has_swim_pool_false THEN TRUE
        WHEN amenities_cnt.has_swim_pool_true < amenities_cnt.has_swim_pool_false THEN FALSE
    END AS has_swim_pool,
    CASE 
        WHEN amenities_cnt.has_sports_court_true = 0 AND amenities_cnt.has_sports_court_false = 0 THEN NULL
        WHEN amenities_cnt.has_sports_court_true >= amenities_cnt.has_sports_court_false THEN TRUE
        WHEN amenities_cnt.has_sports_court_true < amenities_cnt.has_sports_court_false THEN FALSE
    END AS has_sports_court,
    CASE 
        WHEN amenities_cnt.has_gym_true = 0 AND amenities_cnt.has_gym_false = 0 THEN NULL
        WHEN amenities_cnt.has_gym_true >= amenities_cnt.has_gym_false THEN TRUE
        WHEN amenities_cnt.has_gym_true < amenities_cnt.has_gym_false THEN FALSE
    END AS has_gym,
    CASE 
        WHEN amenities_cnt.has_party_hall_true = 0 AND amenities_cnt.has_party_hall_false = 0 THEN NULL
        WHEN amenities_cnt.has_party_hall_true >= amenities_cnt.has_party_hall_false THEN TRUE
        WHEN amenities_cnt.has_party_hall_true < amenities_cnt.has_party_hall_false THEN FALSE
    END AS has_party_hall,
    CASE 
        WHEN amenities_cnt.has_sauna_true = 0 AND amenities_cnt.has_sauna_false = 0 THEN NULL
        WHEN amenities_cnt.has_sauna_true >= amenities_cnt.has_sauna_false THEN TRUE
        WHEN amenities_cnt.has_sauna_true < amenities_cnt.has_sauna_false THEN FALSE
    END AS has_sauna,
    CASE 
        WHEN amenities_cnt.has_laundry_true = 0 AND amenities_cnt.has_laundry_false = 0 THEN NULL
        WHEN amenities_cnt.has_laundry_true >= amenities_cnt.has_laundry_false THEN TRUE
        WHEN amenities_cnt.has_laundry_true < amenities_cnt.has_laundry_false THEN FALSE
    END AS has_laundry,
    CASE 
        WHEN amenities_cnt.has_piped_gas_true = 0 AND amenities_cnt.has_piped_gas_false = 0 THEN NULL
        WHEN amenities_cnt.has_piped_gas_true >= amenities_cnt.has_piped_gas_false THEN TRUE
        WHEN amenities_cnt.has_piped_gas_true < amenities_cnt.has_piped_gas_false THEN FALSE
    END AS has_piped_gas,
    CASE 
        WHEN amenities_cnt.has_gourmet_area_true = 0 AND amenities_cnt.has_gourmet_area_false = 0 THEN NULL
        WHEN amenities_cnt.has_gourmet_area_true >= amenities_cnt.has_gourmet_area_false THEN TRUE
        WHEN amenities_cnt.has_gourmet_area_true < amenities_cnt.has_gourmet_area_false THEN FALSE
    END AS has_gourmet_area,
    CASE 
        WHEN amenities_cnt.has_metro_or_train_close_true = 0 AND amenities_cnt.has_metro_or_train_close_false = 0 THEN NULL
        WHEN amenities_cnt.has_metro_or_train_close_true >= amenities_cnt.has_metro_or_train_close_false THEN TRUE
        WHEN amenities_cnt.has_metro_or_train_close_true < amenities_cnt.has_metro_or_train_close_false THEN FALSE
    END AS has_metro_or_train_close,
    CASE 
        WHEN amenities_cnt.has_toy_library_true = 0 AND amenities_cnt.has_toy_library_false = 0 THEN NULL
        WHEN amenities_cnt.has_toy_library_true >= amenities_cnt.has_toy_library_false THEN TRUE
        WHEN amenities_cnt.has_toy_library_true < amenities_cnt.has_toy_library_false THEN FALSE
    END AS has_toy_library,
    NULL AS has_water_reuse,
    condo_ebdb.construction_year,
    YEAR(condo_ebdb.ts_updated) AS updated_year,
    condo_ebdb.ts_updated,
    YEAR(condo_ebdb.ts_updated) AS year,
    MONTH(condo_ebdb.ts_updated) AS month,
    DAY(condo_ebdb.ts_updated) AS day
    FROM
    condo_ebdb
    JOIN amenities_cnt
        ON condo_ebdb.id = amenities_cnt.id

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
    NULL AS code,
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
    NULL AS has_condo_page,
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
        lat != 'None'
        AND lng != 'None'
)
SELECT
    MD5(CONCAT(id, source)) AS uuid,
    id AS id_source,
    source,
    condo,
    cnpj,
    address,
    number,
    neighborhood,
    zip_code,
    city,
    state,
    lat,
    lng,
    code,
    phone_number,
    dsr,
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
    has_condo_page,
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
    has_water_reuse,
    construction_year,
    updated_year,
    ts_updated,
    year,
    month,
    day
FROM
    base
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id, source ORDER BY ts_updated) = 1