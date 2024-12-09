SELECT
    NULLIF(city_group, '') AS city_group,
    NULLIF(planning_conversion, '') AS planning_conversion,
    NULLIF(planning_operation, '') AS planning_operation,
    NULLIF(planning_cluster, '') AS planning_cluster,
    NULLIF(company_report_origin, '') AS company_report_origin,    
    CAST(REPLACE(NULLIF(prospects, ''), ',', '') AS FLOAT) AS prospects,
    CAST(REPLACE(NULLIF(qualifieds, ''), ',', '') AS FLOAT) AS qualifieds,
    CAST(REPLACE(NULLIF(available_qualifieds, ''), ',', '') AS FLOAT) AS available_qualifieds,
    CAST(REPLACE(NULLIF(opportunities, ''), ',', '') AS FLOAT) AS opportunities,
    CAST(REPLACE(NULLIF(first_listings, ''), ',', '') AS FLOAT) AS first_listings,
    CAST(NULLIF(date, '') AS DATE) AS date
FROM
    datalake_gsheets_raw.sale_supply_budget_2025