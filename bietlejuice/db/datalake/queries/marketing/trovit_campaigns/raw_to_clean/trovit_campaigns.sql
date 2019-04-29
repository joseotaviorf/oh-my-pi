SELECT
  id,
  name,
  clicks,
  desktop_cost,
  mobile_cost,
  total_cost,
  curr_date
FROM datalake_raw.marketing_trovit_campaigns
WHERE dt='{date}' and acc='{account}'