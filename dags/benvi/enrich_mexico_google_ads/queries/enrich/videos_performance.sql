SELECT
    id_external_customer,
    id_video,
    id_ad_group,
    id_campaign,
    ad_group_name,
    campaign_name,
    ad_network_type,
    account_descriptive_name,
    account_snake_case,
    report_type,
    device,
    clicks,
    cost,
    impressions,
    dt_loaded,
    dt_created
FROM
    datalake_google_ads_clean.videos_performance
WHERE 
    account_snake_case LIKE '%mx%'
    AND DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')