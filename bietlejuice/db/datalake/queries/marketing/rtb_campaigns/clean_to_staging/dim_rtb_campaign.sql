SELECT
  case when name='BR_QuintoAndar' then 1 else 0 end as sk_rtb_campaign,
  name as id_campaign,
  status,
  hash,
  url
FROM datalake_clean.marketing_rtb_campaigns
WHERE dt_created  = '{date}' and acc = '{account}'