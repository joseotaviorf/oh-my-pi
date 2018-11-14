CREATE EXTERNAL TABLE datalake_raw.marketing_facebook_ads_ads_insights (
	account_id varchar,
	account_name varchar,
	ad_id varchar,
	ad_name varchar,
	adset_id varchar,
	adset_name varchar,
	campaign_id varchar,
	campaign_name varchar,
	reach varchar,
	impressions varchar,
	clicks varchar,
	spend varchar,
	impression_device varchar,
	date_start varchar,
	date_stop varchar,
	inline_link_clicks varchar)
PARTITIONED BY (
  acc varchar,
  dt varchar)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/facebook_ads/ads_insights/'