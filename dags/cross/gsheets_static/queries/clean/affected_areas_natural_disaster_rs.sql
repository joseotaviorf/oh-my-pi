SELECT
    city_name,
    house_neighborhood,
    key,
    CAST(impacted AS BOOLEAN) AS is_impacted
FROM
    datalake_gsheets_raw.affected_areas_natural_disaster_rs
