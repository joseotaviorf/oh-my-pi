SELECT
    FIRST(id) AS sk_campaign,
    id_external_customer,
    id_campaign,
    campaign_name,
    acc AS account_name,
    labels,
    is_test_campaign,
    report_type,
    load_date,
    NOW() AS ts_load
FROM 
    datalake_marketing_costs.google_campaigns_performance_report
WHERE
    load_date = DATE('{year}-{month}-{day}')
GROUP BY 
    2,3,4,5,6,7,8,9