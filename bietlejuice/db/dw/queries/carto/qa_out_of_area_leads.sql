SELECT
  dl.*,
  lf.mkt_category,
  lf.mkt_flow,
  lf.mkt_completion,
  lf.mkt_origin,
  lf.mkt_channel,
  lf.mkt_platform,
  lf.mkt_medium
FROM fact_house_listing_flows lf
JOIN dim_lead dl
  ON lf.sk_lead = dl.sk_lead
JOIN dim_date dd
  ON dd.sk_date = lf.sk_discard_date
WHERE funnel_drop_reason = 'ForaArea'
  AND dd.date >= CURRENT_DATE - INTERVAL '30 days'
  AND lf.sk_discard_date != -1
  AND lf.sk_prospect_date = -1
  AND dl.lng IS NOT NULL
  AND dl.lat IS NOT NULL
