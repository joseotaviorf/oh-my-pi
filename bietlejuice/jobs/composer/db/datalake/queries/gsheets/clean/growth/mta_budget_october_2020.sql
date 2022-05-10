SELECT
    CAST(budget AS DOUBLE) AS budget,
    city_group,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(is_blocked_budget AS INTEGER) AS is_blocked_budget,
    CAST(week_start AS DATE) AS dt_week_started,
    CAST(month AS DATE) AS dt_month
FROM
    datalake_gsheets_raw.mta_budget