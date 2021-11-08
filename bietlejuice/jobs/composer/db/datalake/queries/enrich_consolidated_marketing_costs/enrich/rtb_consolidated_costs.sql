SELECT    
    INT(year*10000 + month*100 + day) AS id_date,
    sub_campaign_name AS campaign_name,
    account_name,
    sub_campaign_name AS utm_campaign,
    cost AS other_cost,
    cost AS total_cost
FROM 
    datalake_rtb_campaigns_clean.rtb_campaigns
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
