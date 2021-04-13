SELECT
    SHA2(CONCAT(id_external_customer, id, campaign_name, ad_group_name, device), 256) AS id,
    id AS id_keyword,
    id_external_customer,
    id_ad_group,
    id_campaign,
    campaign_name,
    (campaign_name LIKE 'ZEBRA%') AS is_test_campaign,
    ad_group_name,
    clicks,
    cost,
    device,
    impressions,
    keyword_match_type AS match_type,
    labels,
    criteria,
    account_descriptive_name,
    report_type,
    acc,
    load_date,
    dt_created,
    dt_load
FROM 
    datalake_marketing_hub_clean.google_keywords_performance_report
WHERE
    load_date = DATE('{year}-{month}-{day}')