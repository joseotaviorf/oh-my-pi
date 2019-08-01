DROP TABLE IF EXISTS datalake_clean.marketing_twitter_ads_stats;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_twitter_ads_stats(
	id_ad string,
	platform_name string,
	platform_id string,
	impressions string,
	engagements string,
	cost string,
	billed_engagements string,
	clicks string,
	url_clicks string
)
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/twitter_ads/twitter_ads_stats/'

MSCK REPAIR TABLE datalake_clean.marketing_twitter_ads_stats;