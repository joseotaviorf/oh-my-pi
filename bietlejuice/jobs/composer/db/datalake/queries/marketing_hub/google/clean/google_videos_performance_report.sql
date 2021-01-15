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
    acc,
    ReportType AS report_type,
    Day AS load_date,
    DATE(Day) AS dt_load,
    FROM_UNIXTIME(TO_UNIX_TIMESTAMP(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') AS dt_created
FROM
    datalake_marketing_hub_raw.videos_performance_report
WHERE 
    FROM_UNIXTIME(TO_UNIX_TIMESTAMP(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') = DATE('{year}-{month}-{day}')