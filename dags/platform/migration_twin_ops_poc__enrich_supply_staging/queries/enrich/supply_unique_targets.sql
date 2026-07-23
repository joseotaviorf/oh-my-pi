SELECT 
    date,
    city_group,
    campaign_cluster,
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin,  
    CAST(volumes_prospects_unique AS DOUBLE) AS volumes_prospects_unique,
    CAST(volumes_qualifieds_unique AS DOUBLE) AS volumes_qualifieds_unique,
    CAST(volumes_available_qualifieds_unique AS DOUBLE) AS volumes_available_qualifieds_unique,
    CAST(volumes_opportunities_unique AS DOUBLE) AS volumes_opportunities_unique,
    CAST(volumes_first_listings_unique AS DOUBLE) AS volumes_first_listings_unique
FROM 
    scalability_metrics.supply_funnel_unique_target_2026