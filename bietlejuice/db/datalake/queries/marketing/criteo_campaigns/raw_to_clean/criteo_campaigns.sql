SELECT
  advertiser_name,
  campaign_id,
  campaign_name,
  date_format(date_parse(regexp_extract(day,' (\d{2}\/\d{2}\/\d{4})', 1), '%m/%d/%Y'), '%Y-%m-%d') as cost_attribution_date,
  currency,
  clicks,
  impressions,
  audience,
  cost,
  all_sales,
  revenue,
  composition_win,
  cpc
FROM datalake_raw.marketing_criteo_campaigns
WHERE dt_extraction  = '{dt_extraction}'