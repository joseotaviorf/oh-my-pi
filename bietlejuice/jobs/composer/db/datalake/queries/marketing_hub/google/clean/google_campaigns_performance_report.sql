SELECT
    bigint(externalcustomerid) as id_external_customer,
    bigint(campaignid) as id_campaign,
    campaign_name,
    smallint(clicks) as clicks,
    double(cost) as cost,
    tinyint(month) as month,
    tinyint(week) as week,
    tinyint(year) as year,
    device,
    int(impressions) as impressions,
    AccountDescriptiveName as account_descriptive_name,
    labels,
    absolutetopimpressionpercentage as absolute_top_impression_percentage,
    reporttype as report_type,
    acc,
    SearchImpressionShare as search_impression_share,
    date(date) as dt_load,
    date as load_date,
    from_unixtime(to_unix_timestamp(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') as dt_created
FROM 
    datalake_marketing_hub_raw.campaigns_performance_report
WHERE
    from_unixtime(to_unix_timestamp(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') = date('{year}-{month}-{day}')