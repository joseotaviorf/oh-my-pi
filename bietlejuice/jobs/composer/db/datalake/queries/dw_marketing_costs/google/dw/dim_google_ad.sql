SELECT
    FIRST(id) AS sk_ad,
    id_ad,
    acc AS account_name,
    campaign_name,
    ad_group_name,
    account_descriptive_name,
    ad_type,
    is_test_campaign,
    report_type,
    load_date,
    NOW() AS ts_load
FROM 
    datalake_marketing_costs.google_ads_performance_report
WHERE
    load_date = DATE('{year}-{month}-{day}')
GROUP BY 2,3,4,5,6,7,8,9,10