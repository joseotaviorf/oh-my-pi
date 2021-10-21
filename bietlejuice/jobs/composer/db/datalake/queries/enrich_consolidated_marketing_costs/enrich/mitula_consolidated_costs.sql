SELECT
    INT({year}*10000 + {month}*100 + {day}) AS id_date,
    campaign_name,
    account_name,
    campaign_name AS utm_campaign,
    desktop_cost,
    mobile_cost,
    total_cost
FROM
    datalake_lifull_campaigns_clean.mitula_campaigns
WHERE 
    DATE(dt_attribution) = DATE('{year}-{month}-{day}')