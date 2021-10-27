SELECT
    city_group,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(replace(daily_tof_target, ',', '') AS FLOAT) AS daily_tof_target,
    dia,
    week_start,
    month,
    date
FROM
    datalake_gsheets_raw.rental_tof_daily_targets
