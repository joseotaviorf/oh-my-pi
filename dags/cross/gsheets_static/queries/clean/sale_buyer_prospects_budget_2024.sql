SELECT
    city_group,
    hub_offer,
    CAST(REPLACE(new_buyer_prospect, ',', '') AS DECIMAL(16,4)) AS new_buyer_prospect,
    CAST(REPLACE(recovered_buyer_prospect, ',', '') AS DECIMAL(16,4)) AS recovered_buyer_prospect,
    is_rede,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_budget
FROM
    datalake_gsheets_raw.sale_buyer_prospects_budget_2024