DROP TABLE datalake_clean.marketing_rtb_sub_campaigns;

CREATE EXTERNAL TABLE datalake_clean.marketing_rtb_sub_campaigns(
  hash string,
  name string,
  status string,
  is_editable string,
  rate_card_id string,
  updated_at string,
  account_status string,
  placement string,
  account_hash string,
  account_name string,
  account_currency string
)
PARTITIONED BY(
  acc string,
  dt_created string
)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/rtb_ads/marketing_rtb_sub_campaigns'

MSCK REPAIR TABLE datalake_clean.marketing_rtb_sub_campaigns;