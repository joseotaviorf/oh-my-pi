SELECT
    id_house,
    sk_offer,
    contract_group,
    business_context,
    contract_type,
    loc,
    city_group,
    is_high_ticket,
    CAST(REPLACE(closed_deal_value, ',', '') AS DECIMAL(14,2)) AS closed_deal_value,
    CAST(REPLACE(brokerage_fee, ',', '') AS DECIMAL(14,2)) AS brokerage_fee,
    CAST(REPLACE(brokerage_value, ',', '') AS DECIMAL(14,2)) AS brokerage_value,
    CAST(REPLACE(quintoandar_value, ',', '') AS DECIMAL(14,2)) AS quintoandar_value,	
    CAST(REPLACE(agent_value, ',', '') AS DECIMAL(14,2)) AS agent_value,
    TO_DATE(sale_agreement_signed_date) AS dt_sale_agreement_signed,
    TO_DATE(closed_deal_date) AS dt_closed_deal,
    TO_DATE(month) AS dt_month_started
FROM
    datalake_gsheets_raw.closed_deals