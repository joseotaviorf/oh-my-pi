SELECT
    city_group,
    lead_processing_operation,
    supply_mkt_origin_detailed,
    planning_taxonomy,
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin,
    weeks_conversion,
    op2q,
    q2opp,
    opp2fl,
    fl,
    q2avq,
    avq2opp,
    dt_week_started
FROM
    datalake_gsheets_clean.sale_supply_targets_cohort_2024
UNION ALL
SELECT
    region AS ciy_group,
    NULL AS lead_processing_operation,
    NULL AS supply_mkt_origin_detailed,
    NULL AS planning_taxonomy,
    planning_conversion,
    planning_operation,
    planning_cluster,
    company_report_origin, 
    weeks_conversion,    
    op2q,
    q2opp,
    opp2fl,
    fl,
    q2avq,
    avq2opp,
    week_start AS dt_week_started
FROM
    datalake_gsheets_clean.sale_supply_targets_cohort_2025