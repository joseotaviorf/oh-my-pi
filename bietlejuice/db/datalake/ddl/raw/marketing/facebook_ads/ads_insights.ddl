DROP TABLE datalake_raw.marketing_facebook_ads;

CREATE EXTERNAL TABLE datalake_raw.marketing_facebook_ads (
	account_id string,
	account_name string,
	ad_id string,
	ad_name string,
	adset_id string,
	adset_name string,
	campaign_id string,
	campaign_name string,
	reach string,
	impressions string,
	clicks string,
	spend string,
	impression_device string,
	date_start string,
	date_stop string,
	inline_link_clicks string)
PARTITIONED BY (
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
  's3://5a-datalake/raw/marketing/facebook_ads/ads_insights/'

MSCK REPAIR TABLE datalake_raw.marketing_facebook_ads;