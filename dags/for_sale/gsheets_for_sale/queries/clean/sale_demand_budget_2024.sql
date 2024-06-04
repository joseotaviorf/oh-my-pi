SELECT
    city_group,
    hub_offer,
    CAST(REPLACE(visits_booked, ',', '') AS DECIMAL(14,6)) AS visits_booked,
    CAST(REPLACE(visits_completed, ',', '') AS DECIMAL(14,6)) AS visits_completed,
    CAST(REPLACE(offers_submitted, ',', '') AS DECIMAL(14,6)) AS offers_submitted,
    CAST(REPLACE(offers_accepted, ',', '') AS DECIMAL(14,6)) AS offers_accepted,
    CAST(REPLACE(ccv_signed, ',', '') AS DECIMAL(14,6)) AS ccv_signed,
    CAST(REPLACE(new_buyer_prospect, ',', '') AS DECIMAL(14,6)) AS new_buyer_prospect,
    CAST(REPLACE(recovered_buyer_prospect, ',', '') AS DECIMAL(14,6)) AS recovered_buyer_prospect,
    is_rede,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_budget
FROM
    datalake_gsheets_raw.sale_demand_budget_2024
