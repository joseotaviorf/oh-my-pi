SELECT
  cast(campaign_id as integer) as sk_criteo_campaign,
  cast(campaign_id as integer) as id_campaign,
  advertiser_name,
  campaign_name,
  current_timestamp as ts_load
FROM datalake_clean.marketing_criteo_campaigns
WHERE dt_created  = '{date}' and acc = '{account}'