SELECT
    city_group,
    rental_administrator,
    CAST(REPLACE(rf_target, ',', '') AS FLOAT) AS rf_target,
    rf_type,
    TO_DATE(week_start, 'yyyy-M-d') AS dt_week_started,
    TO_DATE(date, 'yyyy-M-d') AS dt_target
FROM
    datalake_gsheets_raw.mexico_rental_flows_targets