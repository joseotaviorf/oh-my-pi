select
    concat(id_external_customer, '-', id, '-', campaign_name) as id,
    id as id_ad,
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
    (campaign_name like 'ZEBRA%') as is_test_campaign,
    load_date,
    dt_created,
    dt_load
from 
    datalake_marketing_hub_clean.google_ads_performance_report
where
    load_date = date('{year}-{month}-{day}')
