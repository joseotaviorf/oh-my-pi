DROP TABLE IF EXISTS datalake_raw.marketing_twitter_ad_groups;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_twitter_ad_groups (
  id string,
  id_campaign string,
  id_account string,
  name string,
  start_time string,
  end_time string,
  created_at string,
  updated_at string,
  entity_status string,
  total_budget_amount_local_micro string,
  bid_amount_local_micro string,
  automatically_select_bid string,
  bid_type string,
  bid_unit string,
  advertiser_domain string,
  advertiser_user_id string,
  categories string,
  charge_by string,
  include_sentiment string,
  lookalike_expansion string,
  objective string,
  optimization string,
  placements string,
  primary_web_event_tag string,
  product_type string,
  tracking_tags string,
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
  's3://5a-datalake/raw/marketing/twitter_ads/ad_groups'

MSCK REPAIR TABLE datalake_raw.marketing_twitter_ad_groups;