SELECT
    partner AS full_name,
    partner_short_name AS short_name,
    brokerage,
    adm_5a AS quintoandar_administration_fee,
    demand_partner_revenue_share AS demand_partner_fee,
    supply_partner_revenue_share AS supply_partner_fee,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_gsheets_clean.forbrokers_3p_partner_conditions
