SELECT
    BIGINT(adGroupAd.ad.id) AS id_ad,
    BIGINT(customer.id) AS id_external_customer,
    BIGINT(adGroup.id) AS id_ad_group,
    BIGINT(campaign.id) AS id_campaign,
    adGroup.name AS ad_group_name,
    adGroupAd.ad.type AS ad_type,
    campaign.name AS campaign_name,
    SMALLINT(metrics.clicks) AS clicks,
    DOUBLE(metrics.costMicros) AS cost,
    adGroupAd.ad.expandedTextAd.description AS description,
    -- adGroupAd.ad.textAd.description1 AS description_one,
    -- adGroupAd.ad.textAd.description2 AS description_two,
    segments.device AS device,
    segments.adNetworkType AS ad_network_type,
    -- adGroupAd.ad.displayUrl AS display_url,
    INT(metrics.impressions) AS impressions,
    -- adGroupAd.ad.imageAd.name AS image_creative_name,
    customer.descriptiveName AS account_descriptive_name,
    report_type,
    account_snake_case,
    CASE
        WHEN LOWER(account_snake_case) LIKE '%mx%' THEN 'MX'
        WHEN account_snake_case IS NULL THEN 'Undefined'
        ELSE 'BR'
    END AS country_code,
    DATE(segments.date) AS dt_loaded,
    dt_created
FROM
    datalake_google_ads_raw.ads_performance
WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
