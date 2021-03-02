SELECT
    account_name,
    campaign_name,
    CAST(desktop_cost AS FLOAT) AS desktop_cost,
    CAST(mobile_cost AS FLOAT) AS mobile_cost,
    CAST(tablet_cost AS FLOAT) AS tablet_cost,
    CAST(date AS DATE) AS dt_cost
FROM
    datalake_gsheets_raw.marketing_costs_manual_costs_google