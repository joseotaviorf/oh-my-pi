SELECT
    INT(year*10000 + month*100 + day) AS id_date,
    campaign_name,
    account_name_snake_case AS account_name,
    campaign_name AS utm_campaign,
    adset_name AS utm_term,
    ad_name AS utm_content,
    SUM(IF(impression_device IN ('ipad','ipod','iphone','android_smartphone','android_tablet'), spend, 0)) AS mobile_cost,
    SUM(IF(impression_device = 'desktop', spend, 0)) AS desktop_cost,
    SUM(IF(impression_device = 'other', spend, 0)) AS other_cost,
    SUM(spend) AS total_cost,
    SUM(impressions) AS impressions,
    SUM(clicks) AS clicks
FROM
    datalake_marketing_costs_clean.facebook_insights
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
GROUP BY 1,2,3,4,5,6
