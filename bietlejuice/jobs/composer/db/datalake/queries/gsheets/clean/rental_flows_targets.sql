SELECT
    city_group,
    CAST(REPLACE(rf_target, ',', '') AS FLOAT) AS rf_target,
    rf_type,
    week_start,
    date
FROM
    datalake_gsheets_raw.rental_flows_targets
