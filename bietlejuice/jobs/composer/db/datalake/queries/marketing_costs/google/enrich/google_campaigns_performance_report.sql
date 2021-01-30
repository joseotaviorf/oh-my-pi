select
    concat(id_external_customer, '-', id_campaign, '-', campaign_name) as id,
    id_external_customer,
    id_campaign,
    campaign_name,
    (campaign_name like 'ZEBRA%') as is_test_campaign,
    clicks,
    cost,
    month,
    week,
    year,
    device,
    impressions,
    account_descriptive_name,
    labels,
    report_type,
    acc,
    load_date,
    dt_created,
    dt_load
from 
    datalake_marketing_hub_clean.google_campaigns_performance_report
where
    load_date = date('{year}-{month}-{day}')