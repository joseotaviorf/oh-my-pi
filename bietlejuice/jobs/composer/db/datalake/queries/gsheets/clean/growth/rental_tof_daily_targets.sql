SELECT
    city_group,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(REPLACE(daily_tof_target, ',', '') AS FLOAT) AS daily_tof_target,
    CAST(dia AS INTEGER) AS day,
    CAST(week_start AS DATE) AS dt_week_started,
    CAST(month AS INTEGER) AS month,
    CAST(date AS DATE) AS dt_target
FROM
    datalake_gsheets_raw.rental_tof_daily_targets