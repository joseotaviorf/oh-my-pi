SELECT
  id,
  name,
  account_name,
  clicks,
  conversions,
  desktop_cost,
  mobile_cost,
  total_cost,
  curr_date
FROM datalake_raw.marketing_lifull_campaigns
WHERE acc='{account}'
    AND group_name='{group_name}'
    AND dt='{date}'