with merge_marketing_hub_with_xplenty as (
    select distinct
        bigint(account_id) as id_external_customer,
        bigint(campaign_id) as id_campaign,
        replace(lcase(campaign_name), '.', '_') as campaign_name,
        smallint(clicks) as clicks,
        double(cost) as cost,
        tinyint(month) as month,
        tinyint(week) as week,
        tinyint(year) as year,
        device,
        int(impressions) as impressions,
        account_name as account_descriptive_name,
        labels,
        float(absolute_top_impression_percentage) as absolute_top_impression_percentage,
        null as search_impression_share,
        'campaigns_performance_report' as report_type,
        acc,
        date as load_date,
        date(dt_created) as dt_created,
        date(date) as dt_load
    from 
        datalake_xplenty_raw.google_campaigns_performance_report
    where
        dt_created = date('{year}-{month}-{day}')

    union all

    select
        id_external_customer,
        id_campaign,
        campaign_name,
        clicks,
        cost,
        month,
        week,
        year,
        device,
        impressions,
        account_descriptive_name,
        labels,
        absolute_top_impression_percentage,
        search_impression_share,
        report_type,
        acc,
        load_date,
        dt_created,
        dt_load
    from 
        datalake_marketing_hub_clean.google_campaigns_performance_report
    where
        load_date = date('{year}-{month}-{day}')
)

select
    concat(id_external_customer, '-', id_campaign, '-', campaign_name) as id,
    *
from
    merge_marketing_hub_with_xplenty