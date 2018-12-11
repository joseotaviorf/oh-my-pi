DROP TABLE datalake_clean.marketing_google_campaigns;

CREATE EXTERNAL TABLE datalake_clean.marketing_google_campaigns (
  account_id string,
  campaign_id string,
  campaign_name string,
  clicks string,
  click_type string,
  cost string,
  date string,
  device string,
  impressions string,
  account_name string,
  hour_of_day string,
  month string,
  labels string,
  week string,
  year string)
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/google_ads/marketing_google_campaigns/'

MSCK REPAIR TABLE datalake_clean.marketing_google_campaigns;