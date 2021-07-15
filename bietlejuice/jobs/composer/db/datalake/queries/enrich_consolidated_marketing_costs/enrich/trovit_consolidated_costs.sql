SELECT
    INT({year}*10000 + {month}*100 + {day}) AS id_date,
    campaign_name,
    account_name,
    campaign_name AS utm_campaign,
    desktop_cost,
    mobile_cost,
    total_cost
FROM
    datalake_trovit_clean.trovit_report
WHERE 
    DATE(dt) = DATE('{year}-{month}-{day}')
