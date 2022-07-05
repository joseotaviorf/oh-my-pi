SELECT
    NULLIF(city, '') AS city,
    NULLIF(business, '') AS business,
    NULLIF(mkt_channel, '') AS mkt_channel,
    NULLIF(mkt_medium, '') AS mkt_medium,
    NULLIF(mkt_source, '') AS mkt_source,
    NULLIF(FLOAT(week_value), '') AS week_value,
    NULLIF(CAST(month AS INTEGER), '') AS month,
    NULLIF(CAST(year AS INTEGER), '') AS year,
    NULLIF(DATE(date), '') AS dt_created,
    NULLIF(DATE(week_start), '') AS dt_week_started
FROM
    datalake_gsheets_raw.mexico_demand_marketing_cost_per_source_actual