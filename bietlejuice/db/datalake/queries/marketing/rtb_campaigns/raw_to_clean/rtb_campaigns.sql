SELECT
  status,
  hash,
  name,
  currency,
  url,
  cast(day as date) as cost_attribution_date,
  impscount,
  clickscount,
  ctr,
  campaigncost,
  conversionscount,
  conversionsrate,
  cpc
FROM datalake_raw.marketing_rtb_campaigns
WHERE dt  = '{date}' and acc = '{account}'