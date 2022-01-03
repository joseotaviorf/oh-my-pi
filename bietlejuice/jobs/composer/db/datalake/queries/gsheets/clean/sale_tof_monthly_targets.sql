SELECT
    city_group,
    context,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(replace(tof_users_target, ',', '') AS FLOAT) AS tof_users_target,
    month_start,
    month,
    year
FROM
    datalake_gsheets_raw.sale_tof_monthly_targets
