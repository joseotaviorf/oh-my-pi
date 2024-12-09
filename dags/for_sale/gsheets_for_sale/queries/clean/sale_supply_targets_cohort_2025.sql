SELECT
    NULLIF(region, '') AS region,
    NULLIF(planning_conversion, '') AS planning_conversion,
    NULLIF(planning_operation, '') AS planning_operation,
    NULLIF(planning_cluster, '') AS planning_cluster,
    NULLIF(company_report_origin, '') AS company_report_origin, 
    NULLIF(weeks_conversion, '') AS weeks_conversion,    
    CAST(REPLACE(NULLIF(op2q, ''), ',', '') AS FLOAT) AS op2q,
    CAST(REPLACE(NULLIF(q2avq, ''), ',', '') AS FLOAT) AS q2avq,
    CAST(REPLACE(NULLIF(avq2opp, ''), ',', '') AS FLOAT) AS avq2opp,
    CAST(REPLACE(NULLIF(opp2fl, ''), ',', '') AS FLOAT) AS opp2fl,
    CAST(REPLACE(NULLIF(fl, ''), ',', '') AS FLOAT) AS fl,
    CAST(REPLACE(NULLIF(q2opp, ''), ',', '') AS FLOAT) AS q2opp,
    CAST(NULLIF(week_start, '') AS DATE) AS week_start
FROM
    datalake_gsheets_raw.sale_supply_targets_cohort_2025