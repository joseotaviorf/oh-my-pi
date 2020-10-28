SELECT
    id as sk_criteo_campaign,
    id_campaign,
    advertiser_name,
    campaign_name,
    currency,
    year,
    month,
    day,
    current_timestamp AS ts_load
FROM datalake_marketing_costs.criteo_campaigns
WHERE year = '{year}' AND month = '{month}' AND day = '{day}'