SELECT
    BIGINT(id) AS id_ad,
    BIGINT(externalcustomerid) AS id_external_customer,
    BIGINT(adgroupid) AS id_ad_group,
    BIGINT(campaignid) AS id_campaign,
    adgroupname AS ad_group_name,
    adtype AS ad_type,
    campaignname AS campaign_name,
    SMALLINT(clicks) AS clicks,
    DOUBLE(cost) AS cost,
    description,
    description1 AS description_one,
    description2 AS description_two,
    device,
    displayurl AS display_url,
    INT(impressions) AS impressions,
    imagecreativename AS image_creative_name,
    AccountDescriptiveName AS account_descriptive_name,
    reporttype AS report_type,
    acc AS account_snake_case,
    DATE(`date`) AS dt_loaded,
    TO_DATE(dt, 'dd-MM-yyyy') AS dt_created
FROM
    datalake_google_ads_cm_raw.ads_performance_report
WHERE
    TO_DATE(dt, 'dd-MM-yyyy') = DATE('{year}-{month}-{day}')
