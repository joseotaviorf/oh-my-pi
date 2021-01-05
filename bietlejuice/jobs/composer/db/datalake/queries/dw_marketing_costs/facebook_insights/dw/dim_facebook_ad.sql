SELECT 
    sk_ad,
    ad_name,
    adset_name,
    campaign_name,
    acc AS account_name,
    is_test_campaign,
    year,
    month,
    day,
    NOW() AS ts_load
FROM 
    datalake_marketing_costs.facebook_insights
WHERE
    year = {year} 
    AND month = {month} 
    AND day = {day}
GROUP BY
    2,3,4,5,6,7,8,9
