SELECT
    SHA2(CONCAT(id_external_customer, id_campaign, campaign_name, device), 256) AS id,
    id_external_customer,
    id_campaign,
    campaign_name,
    (campaign_name LIKE 'ZEBRA%') AS is_test_campaign,
    clicks,
    cost,
    month,
    week,
    year,
    device,
    impressions,
    account_descriptive_name,
    labels,
    report_type,
    acc,
    load_date,
    dt_created,
    dt_load
FROM 
    datalake_marketing_hub_clean.google_campaigns_performance_report
WHERE
    load_date = DATE('{year}-{month}-{day}')