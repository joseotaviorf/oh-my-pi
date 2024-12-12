SELECT
    city_group,
    planning_taxonomy,
    supply_mkt_origin_detailed,
    lead_processing_operation,
    rental_administrator,
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
    datalake_gsheets_clean.supply_targets_retro_cohort
UNION ALL
SELECT
    city_group,
    planning_taxonomy,
    supply_mkt_origin_detailed,
    lead_processing_operation,
    rental_administrator,
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
    datalake_gsheets_clean.supply_targets_2024_cohort
UNION ALL
SELECT
    city_group,
    NULL AS planning_taxonomy,
    NULL AS supply_mkt_origin_detailed,
    NULL AS lead_processing_operation,
    NULL AS rental_administrator,
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
    datalake_gsheets_clean.rent_supply_targets_cohort_2025
