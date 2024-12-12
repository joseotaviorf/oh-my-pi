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
    prospects,
    qualifieds,
    opportunities,
    available_qualifieds,
    first_listings,
    dt_target
FROM
    datalake_gsheets_clean.supply_targets_retro_1
UNION ALL
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
    prospects,
    qualifieds,
    opportunities,
    available_qualifieds,
    first_listings,
    dt_target
FROM
    datalake_gsheets_clean.supply_targets_retro_2
UNION ALL
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
    prospects,
    qualifieds,
    opportunities,
    available_qualifieds,
    first_listings,
    dt_target
FROM
    datalake_gsheets_clean.supply_targets_2024
UNION ALL
SELECT
    city_group,
    NULL AS lead_processing_operation,
    NULL AS supply_mkt_origin_detailed,
    NULL AS planning_taxonomy,
    NULL AS rental_administrator,
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin,
    prospects,
    qualifieds,
    opportunities,
    available_qualifieds,
    first_listings,
    date AS dt_target
FROM
    datalake_gsheets_clean.supply_targets_2025