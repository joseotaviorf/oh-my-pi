SELECT (
  campaign_id as sk_criteo_campaign,
  campaign_id as id_campaign,
  campaign_name,
)
FROM datalake_clean.marketing_criteo_campaigns
WHERE dt_cost_attribution  = '{dt_cost_attribution}'