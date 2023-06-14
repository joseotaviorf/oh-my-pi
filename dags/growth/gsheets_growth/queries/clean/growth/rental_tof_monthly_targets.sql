SELECT
    city_group,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(replace(tof_users_target, ',', '') AS FLOAT) AS tof_users_target,
    TO_DATE(month_start, 'yyyy-MM-dd') AS dt_month_started
FROM
    datalake_gsheets_raw.rental_tof_monthly_targets