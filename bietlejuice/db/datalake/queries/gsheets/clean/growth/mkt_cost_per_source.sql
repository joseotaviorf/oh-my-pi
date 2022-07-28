SELECT
    business,
    city AS city_group,
    CAST(REPLACE(daily_value, ',','') AS FLOAT) AS daily_value,
    mkt_channel,
    mkt_medium,
    mkt_source,
    CAST(date AS DATE) AS dt_event,
    CAST(week_start AS DATE) AS dt_week_start,
    CAST(month AS DATE) AS month,
    year
FROM
    datalake_gsheets_raw.mkt_cost_per_source
