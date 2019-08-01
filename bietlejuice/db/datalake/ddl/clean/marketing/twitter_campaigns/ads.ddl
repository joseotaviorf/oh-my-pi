DROP TABLE IF EXISTS datalake_clean.marketing_twitter_ads;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_twitter_ads(
  id string,
  id_line_item string,
  id_account string,
  tweet_id string,
  approval_status string,
  created_at string,
  updated_at string,
  deleted string,
  entity_status string
)
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/twitter_ads/marketing_twitter_ads/'

MSCK REPAIR TABLE datalake_clean.marketing_twitter_ads;