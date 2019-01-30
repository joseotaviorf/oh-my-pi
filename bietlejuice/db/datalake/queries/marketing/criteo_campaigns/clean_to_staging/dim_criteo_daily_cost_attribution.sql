SELECT
  cast(campaign_id as integer) as sk_criteo_campaign,
  cast(campaign_id as integer) as id_campaign,
  campaign_name
FROM datalake_clean.marketing_criteo_campaigns
WHERE dt_cost_attribution  = '{dt_cost_attribution}'