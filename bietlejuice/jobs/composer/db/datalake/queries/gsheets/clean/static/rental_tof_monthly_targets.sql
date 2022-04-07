SELECT
    city_group,
    mkt_channel,
    mkt_medium,
    mkt_source,
    tof_users_target,
    TO_DATE(month_start, 'yyyy-MM-dd') AS dt_month_started
FROM
    datalake_gsheets_raw.rental_tof_monthly_targets