SELECT
    CAST(id AS BIGINT) AS id_region,
    city_name,
    neighborhood_name,
    concat_city_neighborhood,
    CAST(strategic_region AS BOOLEAN) AS is_strategic_region,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.sale_comission_for_strategic_region


