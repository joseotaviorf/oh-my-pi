SELECT
    date,
    'qts' AS source,
    'RENT' AS business_context,
    city_group, 
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin,  
    CAST(prospects AS DOUBLE) AS prospects,
    CAST(qualifieds AS DOUBLE) AS qualifieds,
    CAST(available_qualifieds AS DOUBLE) AS available_qualifieds,
    CAST(opportunities AS DOUBLE) AS opportunities,
    CAST(first_listings AS DOUBLE) AS first_listings
FROM 
    scalability_metrics.rent_supply_budget_2026
UNION ALL
SELECT
    date,
    'qts' AS source,
    'SALE' AS business_context,
    city_group, 
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin,  
    CAST(prospects AS DOUBLE) as prospects,
    CAST(qualifieds AS DOUBLE) as qualifieds,
    CAST(available_qualifieds AS DOUBLE) as available_qualifieds,
    CAST(opportunities AS DOUBLE) as opportunities,
    CAST(first_listings AS DOUBLE) as first_listings
FROM 
    scalability_metrics.sale_supply_budget_2026
UNION ALL
SELECT
    date,
    'okr' AS source,
    'RENT' AS business_context,
    city_group,
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin,
    CAST(prospects AS DOUBLE) AS prospects,
    CAST(qualifieds AS DOUBLE) AS qualifieds,
    CAST(available_qualifieds AS DOUBLE) AS available_qualifieds,
    CAST(opportunities AS DOUBLE) AS opportunities,
    CAST(first_listings AS DOUBLE) AS first_listings
FROM 
    scalability_metrics.rent_supply_okr_2026
UNION ALL
SELECT
    date,
    'okr' AS source,
    'SALE' AS business_context,
    city_group, 
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin,  
    CAST(prospects AS DOUBLE) AS prospects,
    CAST(qualifieds AS DOUBLE) AS qualifieds,
    CAST(available_qualifieds AS DOUBLE) AS available_qualifieds,
    CAST(opportunities AS DOUBLE) AS opportunities,
    CAST(first_listings AS DOUBLE) AS first_listings
FROM 
  scalability_metrics.sale_supply_okr_2026