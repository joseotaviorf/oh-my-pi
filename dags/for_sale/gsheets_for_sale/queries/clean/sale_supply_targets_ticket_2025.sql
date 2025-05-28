SELECT
    NULLIF(city_group, '') AS city_group,
    NULLIF(planning_conversion, '') AS planning_conversion,
    NULLIF(planning_operation, '') AS planning_operation,
    NULLIF(planning_cluster, '') AS planning_cluster,
    NULLIF(company_report_origin, '') AS company_report_origin,
    NULLIF(range_tkt_adj, '') AS range_tkt_adj,
    NULLIF(tkt_range, '') AS tkt_range,
    CAST(REPLACE(NULLIF(volume_first_listings, ''), ',', '') AS FLOAT) AS volume_first_listings,
    CAST(NULLIF(date, '') AS DATE) AS date, 
    CAST(NULLIF(week, '') AS DATE) AS week, 
    CAST(NULLIF(year_month, '') AS DATE) AS year_month
FROM
    datalake_gsheets_raw.sale_supply_targets_ticket_2025