SELECT
    bigint(id) as id,
    bigint(externalcustomerid) as id_external_customer,
    bigint(adgroupid) as id_ad_group,
    bigint(campaignid) as id_campaign,
    campaignname as campaign_name,
    adgroupname as ad_group_name,
    smallint(clicks) as clicks,
    double(cost) as cost,
    device,
    int(impressions) as impressions,
    keywordmatchtype as keyword_match_type,
    labels,
    criteria,
    AccountDescriptiveName as account_descriptive_name,
    reporttype as report_type,
    acc,
    date(date) as dt_load,
    date as load_date,
    from_unixtime(to_unix_timestamp(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') as dt_created
FROM 
    datalake_marketing_hub_raw.keywords_performance_report
WHERE
    from_unixtime(to_unix_timestamp(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') = date('{year}-{month}-{day}')