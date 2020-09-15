SELECT
    bigint(id),
    bigint(externalcustomerid) as id_external_customer,
    bigint(adgroupid) as id_ad_group,
    bigint(campaignid) as id_campaign,
    adgroupname as ad_group_name,
    adtype as ad_type,
    campaign_name,
    smallint(clicks) as clicks,
    double(cost) as cost,
    description,
    description1 as description_one,
    description2 as description_two,
    device,
    displayurl as display_url,
    int(impressions) as impressions,
    imagecreativename as image_creative_name,
    AccountDescriptiveName as account_descriptive_name,
    float(AbsoluteTopImpressionPercentage) as absolute_top_impression_percentage,
    reporttype as report_type,
    acc,
    date(date) as dt_load,
    date as load_date,
    from_unixtime(to_unix_timestamp(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') as dt_created
FROM 
    datalake_marketing_hub_raw.ads_performance_report
WHERE 
    from_unixtime(to_unix_timestamp(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') = date('{year}-{month}-{day}')