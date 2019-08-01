DROP TABLE IF EXISTS datalake_clean.marketing_twitter_campaigns;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_twitter_campaigns(
	id string,
	name string,
	id_account string,
	account_name string,
	start_time string,
	end_time string,
	created_at string,
	updated_at string,
	entity_status string,
	duration_in_days string,
	total_budget string,
	daily_budget string,
	standard_delivery string,
	currency string,
	servable string,
	funding_instrument_id string,
	reasons_not_servable string,
	frequency_cap string,
	to_delete string,
	deleted string
)
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/twitter_ads/twitter_campaigns/'

MSCK REPAIR TABLE datalake_clean.marketing_twitter_campaigns;