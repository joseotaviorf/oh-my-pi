with merge_marketing_hub_with_xplenty as (
    select distinct
        bigint(ad_id) as id_ad,
        bigint(account_id) as id_external_customer,
        bigint(adgroup_id) as id_ad_group,
        bigint(campaign_id) as id_campaign,
        adgroup_name as ad_group_name,
        ad_type,
        smallint(clicks) as clicks,
        double(cost) as cost,
        description,
        description1 as description_one,
        description2 as description_two,
        device,
        null as display_url,
        int(impressions) as impressions,
        image_creative_name as account_descriptive_name,
        account_name,
        float(absolute_top_impression_percentage) as absolute_top_impression_percentage,
        'ads_performance_report' as report_type,
        acc,
        campaign_name,
        date as load_date,
        date(dt_created) as dt_created,
        date(date) as dt_load
    from 
        datalake_xplenty_raw.google_ads_performance_report
    where
        date = date('{year}-{month}-{day}')

    union all

    select
        id,
        id_external_customer,
        id_ad_group,
        id_campaign,
        ad_group_name,
        ad_type,
        clicks,
        cost,
        description,
        description_one,
        description_two,
        device,
        display_url,
        impressions,
        image_creative_name,
        account_descriptive_name,
        absolute_top_impression_percentage,
        report_type,
        acc,
        campaign_name,
        load_date,
        dt_created,
        dt_load
    from 
        datalake_marketing_hub_clean.google_ads_performance_report
    where
        load_date = date('{year}-{month}-{day}')
)

select
    concat(id_external_customer, '-', id_ad, '-', campaign_name) as id,
    *
from
    merge_marketing_hub_with_xplenty
