select
  subcampaign as sub_campaign,
  subcampaignhash as sub_campaign_hash,
  cast("day" as date) as cost_attribution_date,
  devicetype as device_type,
  impscount as impressions_count,
  clickscount as clicks_count,
  ctr,
  campaigncost as cost,
  conversionscount as conversions_count,
  cr,
  cpc,
  ecps,
  ecc,
  roas,
  conversionsvalue as conversions_value,
  account_name string,
  account_hash string,
  account_status string,
  account_currency string
from datalake_raw.marketing_rtb_stats
where dt='{date}' and acc='{account}'