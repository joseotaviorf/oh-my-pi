SELECT
    op,
    cidade AS city,
    first_listing,
    mkt_origin,
    operacao AS operation,
    opportunity,
    qualified,
    week_origin,
    DATE(week) AS dt_week
FROM
    datalake_gsheets_raw.target_sale_cohort_supply