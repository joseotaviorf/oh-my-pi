SELECT
  f.*,
  d.campaign_name,
  d.campaign_description,
  d.schedule_type,
  d.is_archived,
  d.is_draft,
  d.ts_first_sent,
  d.ts_last_sent,
  d.ts_created,
  d.ts_updated,
  ROW_NUMBER() OVER (PARTITION BY f.sk_user_dispatch, f.sk_campaign ORDER BY f.ts_load DESC) AS row_number
FROM dw_braze.fact_campaign_user_dispatch AS f
LEFT JOIN dw_braze.dim_campaign AS d
  ON f.sk_campaign = d.sk_campaign