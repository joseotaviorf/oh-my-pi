SELECT
    city_group,
    lead_processing_operation,
    supply_mkt_origin_detailed,
    planning_taxonomy,
    rental_administrator,
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin,
    CAST(REPLACE(prospects, ',', '') AS DECIMAL(14,6)) AS prospects,
    CAST(REPLACE(qualifieds, ',', '') AS DECIMAL(14,6)) AS qualifieds,
    CAST(REPLACE(opportunities, ',', '') AS DECIMAL(14,6)) AS opportunities,
    CAST(REPLACE(available_qualifieds, ',', '') AS DECIMAL(14,6)) AS available_qualifieds,
    CAST(REPLACE(first_listings, ',', '') AS DECIMAL(14,6)) AS first_listings,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_budget
FROM
    datalake_gsheets_raw.rent_supply_budget_2024
