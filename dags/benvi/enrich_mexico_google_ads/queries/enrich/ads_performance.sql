SELECT
    id_ad,
    id_external_customer,
    id_ad_group,
    id_campaign,
    ad_group_name,
    ad_type,
    campaign_name,
    description,
    device,
    ad_network_type,
    account_descriptive_name,
    report_type,
    account_snake_case,
    clicks,
    cost,
    impressions,
    dt_loaded,
    dt_created
FROM
    datalake_google_ads_clean.ads_performance
WHERE
    account_snake_case LIKE '%mx%'
    AND DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')