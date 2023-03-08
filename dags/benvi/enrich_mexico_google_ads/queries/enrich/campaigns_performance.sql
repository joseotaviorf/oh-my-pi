SELECT
    id_external_customer,
    id_campaign,
    campaign_name,
    ad_network_type,
    account_descriptive_name,
    labels,
    report_type,
    account_snake_case,
    device,
    clicks,
    cost,
    impressions,
    month,
    week,
    year,
    dt_loaded,
    dt_created
FROM
    datalake_google_ads_clean.campaigns_performance
WHERE
    account_snake_case LIKE '%mx%'
    AND DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')