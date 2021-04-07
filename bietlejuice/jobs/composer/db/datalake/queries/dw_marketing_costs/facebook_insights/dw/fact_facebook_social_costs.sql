SELECT 
    sk_ad,
    clicks,
    cpc,
    cpm,
    impressions,
    reach,
    dt_start,
    dt_stop,
    year,
    month,
    day,
    NOW() AS ts_load
FROM 
    datalake_marketing_costs.facebook_social_insights
WHERE
    year = {year} 
    AND month = {month} 
    AND day = {day}
GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12