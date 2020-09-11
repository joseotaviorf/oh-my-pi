with merge_marketing_hub_with_xplenty as (
    select distinct
        bigint(keyword_id) as id_keyword,
        bigint(account_id) as id_external_customer,
        bigint(adgroup_id) as id_ad_group,
        bigint(campaign_id) as id_campaign,
        campaign_name,
        adgroup_name as ad_group_name,
        smallint(clicks) as clicks,
        double(cost) as cost,
        device,
        int(impressions) as impressions,
        match_type,
        labels,
        criteria,
        account_name as account_descriptive_name,
        float(absolute_top_impression_percentage) as absolute_top_impression_percentage,
        float(search_impression_share) as search_impression_share,
        null as report_type,
        acc,
        date as load_date,
        dt_created,
        date(date) as dt_load
    from 
        datalake_xplenty_raw.google_keywords_performance_report
    where
        date = date('{year}-{month}-{day}')

    union all

    select
        id,
        id_external_customer,
        id_ad_group,
        id_campaign,
        campaign_name,
        ad_group_name,
        clicks,
        cost,
        device,
        impressions,
        keyword_match_type,
        labels,
        criteria,
        account_descriptive_name,
        absolute_top_impression_percentage,
        search_impression_share,
        report_type,
        acc,
        load_date,
        dt_created,
        dt_load
    from 
        datalake_marketing_hub_clean.google_keywords_performance_report
    where
        load_date = date('{year}-{month}-{day}')
)

select
    concat(id_external_customer, '-', id_keyword, '-', campaign_name) as id,
    *
from
    merge_marketing_hub_with_xplenty