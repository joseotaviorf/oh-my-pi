SELECT    
    INT(year*10000 + month*100 + day) AS id_date,
    sub_campaign AS campaign_name,
    account_name,
    sub_campaign AS utm_campaign,
    cost AS other_cost,
    cost AS total_cost
FROM 
    datalake_marketing_costs_clean.rtb_campaigns
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
