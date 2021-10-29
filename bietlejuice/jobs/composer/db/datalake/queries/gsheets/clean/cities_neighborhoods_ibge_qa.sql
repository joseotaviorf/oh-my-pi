SELECT
    NULLIF(city_name, '') AS city_name_qa,
    NULLIF(city_group, '') AS city_group_qa,
    NULLIF(region_code, '') AS region_code_qa,
    NULLIF(name, '') AS neighborhood_name_qa,
    NULLIF(nm_bairro, '') AS neighborhood_name_ibge,
    NULLIF(nm_municip, '') AS city_name_ibge,
    NULLIF(nm_micro, '') AS microregion_name_ibge,
    CAST(V002 AS INTEGER) AS total_private_households,
    CAST(V008 AS INTEGER) AS rented_private_households,
    CAST(V180 AS INTEGER) AS apartment_rented_private_households,
    CAST(date AS DATE) AS dt_reference
FROM
    datalake_gsheets_raw.cities_neighborhoods_ibge_qa
