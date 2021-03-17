SELECT
    FIRST(id) AS sk_keyword,
    id_keyword AS id_keyword,
    criteria AS keyword_name,
    acc AS account_name,
    campaign_name,
    ad_group_name,
    match_type,
    is_test_campaign,
    report_type,
    load_date,
    NOW() AS ts_load
FROM 
    datalake_marketing_costs.google_keywords_performance_report
WHERE
    load_date = DATE('{year}-{month}-{day}')
GROUP BY
    2,3,4,5,6,7,8,9,10