DROP TABLE datalake_clean.marketing_rtb_campaigns;

CREATE EXTERNAL TABLE datalake_clean.marketing_rtb_campaigns (
    status string,
    hash string,
    name string,
    currency string,
    url string,
    cost_attribution_date string,
    impressions_count string,
    clicks_count string,
    ctr string,
    campaign_cost string,
    conversions_count string,
    conversions_rate string,
    cpc string
  )
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/rtb_campaigns/marketing_rtb_campaigns/'

MSCK REPAIR TABLE datalake_clean.marketing_rtb_campaigns;