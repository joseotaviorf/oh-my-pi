select
    concat(id_external_customer, '-', id, '-', campaign_name) as id,
    id AS id_keyword,
    id_external_customer,
    id_ad_group,
    id_campaign,
    campaign_name,
    (campaign_name like 'ZEBRA%') as is_test_campaign,
    ad_group_name,
    clicks,
    cost,
    device,
    impressions,
    keyword_match_type AS match_type,
    labels,
    criteria,
    account_descriptive_name,
    report_type,
    acc,
    load_date,
    dt_created,
    dt_load
from 
    datalake_marketing_hub_clean.google_keywords_performance_report
where
    load_date = date('{year}-{month}-{day}')