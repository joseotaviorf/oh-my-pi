DROP TABLE datalake_clean.marketing_rtb_campaigns;

CREATE EXTERNAL TABLE datalake_clean.marketing_rtb_campaigns (
  cost_attribution_date string,
  impressions string,
  clicks string,
  ctr string,
  conversions_count string,
  conversions_rate string,
  cpc string,
  ecc string,
  roas string,
  conversions_value
  )
PARTITIONED BY (
  dt_cost_attribution string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/rtb_campaigns/all/'

MSCK REPAIR TABLE datalake_clean.marketing_rtb_campaigns;