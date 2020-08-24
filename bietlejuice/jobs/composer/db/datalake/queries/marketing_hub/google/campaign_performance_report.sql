SELECT
    bigint(externalcustomerid) as id_external_customer,
    bigint(campaignid) as id_campaign,
    campaignname as campaign_name,
    smallint(clicks) as clicks,
    double(cost) as cost,
    tinyint(month) as month,
    tinyint(week) as week,
    tinyint(year) as year,
    device,
    impressions,
    account_descriptive_name as account_descriptive_name,
    labels,
    absolutetopimpressionpercentage as absolute_top_impression_percentage,
    reporttype as report_type,
    acc,
    date(date) as dt_load,
    date as load_date,
    from_unixtime(to_unix_timestamp(dt, 'dd-MM-yyyy'), 'yyyy-MM-dd') as dt_created
FROM 
    datalake_marketing_hub_raw.campaign_performance_report
WHERE
    date = date('{year}-{month}-{day}')