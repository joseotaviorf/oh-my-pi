SELECT
    dc.uuid_company,
    pc.partner AS full_name,
    pc.partner_short_name AS short_name,
    pc.brokerage,
    pc.adm_5a AS quintoandar_administration_fee,
    pc.demand_partner_revenue_share AS demand_partner_fee,
    pc.supply_partner_revenue_share AS supply_partner_fee,
    COALESCE(LAG(DATE_ADD(pc.dt_category_end, 1)) OVER(PARTITION BY pc.partner_short_name ORDER BY COALESCE(pc.dt_category_end, CURRENT_DATE)), DATE('2021-01-01')) AS category_start_date,
    pc.dt_category_end AS category_end_date,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_gsheets_clean.forbrokers_3p_partner_conditions AS pc
LEFT JOIN
    dw_rede.dim_company AS dc
        ON pc.partner_short_name = dc.extracted_3p_tag
        AND NOT dc.is_archived
        AND dc.uuid_company is not null
