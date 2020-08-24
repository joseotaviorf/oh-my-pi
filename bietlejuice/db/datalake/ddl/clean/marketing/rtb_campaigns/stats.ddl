DROP TABLE datalake_clean.marketing_rtb_stats;

CREATE EXTERNAL TABLE datalake_clean.marketing_rtb_stats (
  sub_campaign string,
  sub_campaign_hash string,
  cost_attribution_date string,
  device_type string,
  impressions_count string,
  clicks_count string,
  ctr string,
  cost string,
  conversions_count string,
  cr string,
  cpc string,
  ecps string,
  ecc string,
  roas string,
  conversions_value string,
  account_name string,
  account_hash string,
  account_status string,
  account_currency string
)
PARTITIONED BY (
  acc string,
  dt_created string
)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/rtb_ads/marketing_rtb_stats/'

MSCK REPAIR TABLE datalake_clean.marketing_rtb_stats;