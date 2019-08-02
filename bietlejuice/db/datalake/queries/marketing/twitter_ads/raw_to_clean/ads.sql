SELECT
  id,
  id_line_item,
  id_account,
  tweet_id,
  approval_status,
  created_at,
  updated_at,
  deleted,
  entity_status
FROM datalake_raw.marketing_twitter_ads
WHERE dt='{date}' and acc='{account}'