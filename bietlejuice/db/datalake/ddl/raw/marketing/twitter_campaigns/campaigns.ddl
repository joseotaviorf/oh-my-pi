DROP TABLE IF EXISTS datalake_raw.marketing_twitter_campaigns;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_twitter_campaigns (
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
	total_budget_amount_local_micro string,
	daily_budget_amount_local_micro string,
	standard_delivery string,
	currency string,
	servable string,
	funding_instrument_id string,
	reasons_not_servable string,
	frequency_cap string,
	to_delete string,
	deleted string
) PARTITIONED BY (
  acc string,
  dt string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/twitter_ads/campaigns'

MSCK REPAIR TABLE datalake_raw.marketing_twitter_campaigns;