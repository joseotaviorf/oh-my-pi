DROP TABLE datalake_clean.marketing_criteo_campaigns;

CREATE EXTERNAL TABLE datalake_clean.marketing_criteo_campaigns (
  advertiser_name string,
  campaign_id string,
  campaign_name string,
  cost_attribution_date string,
  currency string,
  clicks string,
  impressions string,
  audience string,
  cost string,
  all_sales string,
  revenue string,
  composition_win string,
  cpc string)
PARTITIONED BY (
  dt_cost_attribution string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/criteo_campaigns/all/'

MSCK REPAIR TABLE datalake_clean.marketing_criteo_campaigns;