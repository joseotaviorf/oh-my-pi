SELECT DISTINCT
  id_campaign AS sk_campaign,
  'affiliates' AS user_type,
  campaign_name,
  campaign_description,
  schedule_type,
  CAST(archived AS BOOLEAN) AS is_archived,
  CAST(draft AS BOOLEAN) AS is_draft,
  ts_first_sent,
  ts_last_sent,
  ts_created,
  ts_updated,
  NOW() AS ts_load
FROM
   datalake_braze_details_clean.campaign_details_indica_ai

UNION ALL

SELECT DISTINCT
  id_campaign AS sk_campaign,
  'owners' AS user_type,
  campaign_name,
  campaign_description,
  schedule_type,
  CAST(archived AS BOOLEAN) AS is_archived,
  CAST(draft AS BOOLEAN) AS is_draft,
  ts_first_sent,
  ts_last_sent,
  ts_created,
  ts_updated,
  NOW() AS ts_load
FROM
   datalake_braze_details_clean.campaign_details_owners

UNION ALL

SELECT DISTINCT
  id_campaign AS sk_campaign,
  'tenants' AS user_type,
  campaign_name,
  campaign_description,
  schedule_type,
  CAST(archived AS BOOLEAN) AS is_archived,
  CAST(draft AS BOOLEAN) AS is_draft,
  ts_first_sent,
  ts_last_sent,
  ts_created,
  ts_updated,
  NOW() AS ts_load
FROM
   datalake_braze_details_clean.campaign_details_tenants
