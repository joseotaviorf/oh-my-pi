SELECT    
    INT(year*10000 + month*100 + day) AS id_date,
    campaign_name,
    account_name,
    campaign_name AS utm_campaign,
    LOWER(SPLIT(campaign_name, '\\.')[3]) AS campaign_city,
    adset_name AS utm_term,
    ad_name AS utm_content,
    SUM(IF(impression_device IN('ipad','ipod','iphone','android_smartphone','android_tablet'), COALESCE(spend,0),0)) AS mobile_cost,
    SUM(IF(impression_device = 'desktop', COALESCE(spend,0),0)) AS desktop_cost,
    SUM(IF(impression_device = 'other', COALESCE(spend,0),0)) AS other_cost,
    SUM(COALESCE(spend,0)) AS total_cost
FROM 
    datalake_marketing_costs.facebook_insights
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
GROUP BY 1,2,3,4,5,6,7