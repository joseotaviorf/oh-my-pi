SELECT
    city_group,
    lead_processing_operation,
    supply_mkt_origin_detailed,
    planning_taxonomy,
    prospects,
    qualifieds,
    opportunities,
    available_qualifieds,
    first_listings,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_target
FROM
    datalake_gsheets_raw.sale_supply_targets_retro
