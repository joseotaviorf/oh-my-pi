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
    TO_DATE(date, 'yyyy-MM-dd') AS dt_target
FROM
    datalake_gsheets_raw.supply_targets_2024
