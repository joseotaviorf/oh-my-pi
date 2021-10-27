SELECT
    city_group,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(replace(tof_users_target, ',', '') AS FLOAT) AS tof_users_target,
    month_start
FROM
    datalake_gsheets_raw.rental_tof_monthly_targets
