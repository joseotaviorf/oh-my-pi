DROP TABLE IF EXISTS datalake_clean.marketing_twitter_ad_groups;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_twitter_ad_groups(
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
  audience_expansion string,
  objective string,
  optimization string,
  placements string,
  primary_web_event_tag string,
  product_type string,
  tracking_tags string,
  to_delete string,
  deleted string
)
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/twitter_ads/marketing_twitter_ad_groups/'

MSCK REPAIR TABLE datalake_clean.marketing_twitter_ad_groups;