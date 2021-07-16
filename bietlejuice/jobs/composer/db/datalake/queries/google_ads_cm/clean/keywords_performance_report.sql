SELECT
    BIGINT(id) AS id_keyword,
    BIGINT(externalcustomerid) AS id_external_customer,
    BIGINT(adgroupid) AS id_ad_group,
    BIGINT(campaignid) AS id_campaign,
    campaignname AS campaign_name,
    adgroupname AS ad_group_name,
    SMALLINT(clicks) AS clicks,
    DOUBLE(cost) AS cost,
    device,
    INT(impressions) AS impressions,
    keywordmatchtype AS match_type,
    labels,
    criteria,
    AccountDescriptiveName AS account_descriptive_name,
    reporttype AS report_type,
    acc AS account_snake_case,
    DATE(`date`) AS dt_loaded,
    TO_DATE(dt, 'dd-MM-yyyy') AS dt_created
FROM
    datalake_google_ads_cm_raw.keywords_performance_report
WHERE
    TO_DATE(dt, 'dd-MM-yyyy') = DATE('{year}-{month}-{day}')
