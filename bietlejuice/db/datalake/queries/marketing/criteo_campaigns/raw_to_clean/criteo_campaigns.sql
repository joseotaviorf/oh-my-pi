SELECT
  "advertiser name",
  "campaign id",
  "campaign name",
  date_format(date_parse(regexp_extract("day",' (\d+\/\d+\/\d+)', 1), '%m/%d/%Y'), '%Y-%m-%d') as cost_attribution_date,
  "currency",
  "clicks",
  "impressions",
  "audience",
  "cost",
  "all sales",
  "revenue",
  "comp. win",
  "cpc"
FROM datalake_raw.marketing_criteo_campaigns
WHERE dt  = '{date}' and acc = '{account}'