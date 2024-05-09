SELECT
    city_name,
    house_neighborhood,
    key,
    CAST(impacted AS BOOLEAN) AS is_impacted
FROM
    datalake_gsheets_raw.affiliates_acquisition_targets
