SELECT
    BIGINT(customer.id) AS id_external_customer,
    video.id AS id_video,
    BIGINT(adGroup.id) AS id_ad_group,
    BIGINT(campaign.id) AS id_campaign,
    adGroup.name AS ad_group_name,
    campaign.name AS campaign_name,
    metrics.clicks AS clicks,
    metrics.costMicros AS cost,
    segments.device AS device,
    metrics.impressions AS impressions,
    customer.descriptiveName AS account_descriptive_name,
    account_snake_case,
    report_type,
    DATE(segments.date) AS dt_loaded,
    dt_created
FROM
    datalake_casa_mineira_google_ads_raw.videos_performance
WHERE
    DATE(dt_created) = DATE('{year}-{month}-{day}')
