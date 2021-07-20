SELECT
    BIGINT(ExternalCustomerID) AS id_external_customer,
    VideoID AS id_video,
    BIGINT(AdGroupID) AS id_ad_group,
    BIGINT(CampaignID) AS id_campaign,
    AdGroup AS ad_group_name,
    Campaign AS campaign_name,
    Clicks AS clicks,
    Cost AS cost,
    Device AS device,
    Impressions AS impressions,
    Account AS account_descriptive_name,
    acc AS account_snake_case,
    ReportType AS report_type,
    DATE(Day) AS dt_loaded,
    TO_DATE(dt, 'dd-MM-yyyy') AS dt_created
FROM
    datalake_casa_mineira_google_ads_raw.videos_performance_report
WHERE 
    TO_DATE(dt, 'dd-MM-yyyy') = DATE('{year}-{month}-{day}') 
