select
  subcampaign as sub_campaign,
  coalesce(subcampaignhash, 'kwKe') as sub_campaign_hash,
  cast("day" as date) as cost_attribution_date,
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
  account_name,
  account_hash,
  account_status,
  account_currency
from datalake_raw.marketing_rtb_stats
where dt='{date}' and acc='{account}'