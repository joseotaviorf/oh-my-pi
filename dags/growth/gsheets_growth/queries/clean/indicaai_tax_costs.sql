SELECT
    NULLIF(table, '') AS table_name,
    NULLIF(mkt_origin, '') AS mkt_origin,
    NULLIF(city_group, '') AS city_group,
    NULLIF(vertical, '') AS vertical,
    NULLIF(source, '') AS source,
    NULLIF(business_context, '') AS business_context,
    CAST(NULLIF(costs, '') AS FLOAT) AS costs,
    CAST(NULLIF(date, '') AS DATE) AS dt_tax_cost,
    CAST(NULLIF(week_start, '') AS DATE) AS dt_week_started
FROM datalake_gsheets_raw.indicaai_tax_costs
