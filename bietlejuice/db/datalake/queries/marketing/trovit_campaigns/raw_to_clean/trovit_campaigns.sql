SELECT
  id,
  name,
  clicks,
  cost,
  curr_date
FROM datalake_raw.marketing_trovit_campaigns
WHERE dt='{date}' and acc='{account}'