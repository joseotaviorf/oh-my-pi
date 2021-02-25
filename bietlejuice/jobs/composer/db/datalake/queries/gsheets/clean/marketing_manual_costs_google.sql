SELECT
    account_name,
    campaign_name,
    CAST(desktop_cost AS DOUBLE) AS desktop_cost,
    CAST(mobile_cost AS DOUBLE) AS mobile_cost,
    CAST(tablet_cost AS DOUBLE) AS tablet_cost,
    DATE(date) AS dt_campaign_cost,
    NOW() AS ts_load
FROM 
    datalake_gsheets_raw.marketing_manual_costs_google