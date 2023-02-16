SELECT
    partner AS full_name,
    partner_short_name AS short_name,
    brokerage,
    adm_5a AS quintoandar_administration_fee,
    demand_partner_revenue_share AS demand_partner_fee,
    supply_partner_revenue_share AS supply_partner_fee,
    COALESCE(LAG(DATE_ADD(dt_category_end, 1)) OVER(PARTITION BY partner_short_name ORDER BY COALESCE(dt_category_end, CURRENT_DATE)), DATE('2021-01-01')) AS category_start_date,
    dt_category_end AS category_end_date,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_gsheets_clean.forbrokers_3p_partner_conditions
