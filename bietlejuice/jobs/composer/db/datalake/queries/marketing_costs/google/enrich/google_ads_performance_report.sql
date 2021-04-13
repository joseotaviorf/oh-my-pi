SELECT
    SHA2(CONCAT(id_external_customer, id, campaign_name, ad_group_name, device), 256) AS id,
    id AS id_ad,
    id_external_customer,
    id_ad_group,
    id_campaign,
    ad_group_name,
    ad_type,
    clicks,
    cost,
    description,
    description_one,
    description_two,
    device,
    display_url,
    impressions,
    image_creative_name AS account_descriptive_name,
    account_descriptive_name AS account_name,
    report_type,
    acc,
    campaign_name,
    (campaign_name LIKE 'ZEBRA%') AS is_test_campaign,
    load_date,
    dt_created,
    dt_load
FROM 
    datalake_marketing_hub_clean.google_ads_performance_report
WHERE
    load_date = DATE('{year}-{month}-{day}')
