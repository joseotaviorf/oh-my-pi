SELECT    
    INT(DATE_FORMAT(dt_attribution, 'YYYYMMdd')) AS id_date,
    sub_campaign_name AS campaign_name,
    account_name,
    sub_campaign_name AS utm_campaign,
    cost AS other_cost,
    cost AS total_cost,
    impressions,
    clicks
FROM 
    datalake_casa_mineira_rtb_campaigns_clean.rtb_campaigns
WHERE
    dt_attribution = DATE('{year}-{month}-{day}')