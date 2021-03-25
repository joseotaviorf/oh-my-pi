SELECT
    CAST(id AS INTEGER) AS id,
    neighbourhood,
    city, 
    region_code, 
    region_code_deprecated,
    region_code_inspector,
    state,
    city_group,
    CAST(DDD AS INTEGER) AS ddd,
    regional,
    regional_deprecated,
    regional_inspection,
    CAST(tier AS INTEGER) AS tier
FROM
    datalake_gsheets_raw.aux_regiao