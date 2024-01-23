SELECT
    city_group,
    planning_taxonomy,
    supply_mkt_origin_detailed,
    lead_processing_operation,
    weeks_conversion,
    op2q,
    q2opp,
    opp2fl,
    fl,
    q2avq,
    avq2opp,
    TO_DATE(week_start, 'yyyy-MM-dd') AS dt_week_started
FROM
    datalake_gsheets_raw.sale_supply_targets_retro_cohort
