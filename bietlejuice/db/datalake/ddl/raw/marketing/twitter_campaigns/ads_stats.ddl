DROP TABLE IF EXISTS datalake_raw.marketing_twitter_ads_stats;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_twitter_ads_stats (
  id_ad string,
  segment_name string,
  segment_value string,
  all_on_twitter_billed_engagements array<string>,
  all_on_twitter_billed_charge_local_micro array<string>,
  all_on_twitter_carousel_swipes array<string>,
  all_on_twitter_likes array<string>,
  all_on_twitter_poll_card_vote array<string>,
  all_on_twitter_follows array<string>,
  all_on_twitter_card_engagements array<string>,
  all_on_twitter_qualified_impressions array<string>,
  all_on_twitter_retweets array<string>,
  all_on_twitter_replies array<string>,
  all_on_twitter_tweets_send array<string>,
  all_on_twitter_impressions array<string>,
  all_on_twitter_engagements array<string>,
  all_on_twitter_unfollows array<string>,
  all_on_twitter_app_clicks array<string>,
  all_on_twitter_url_clicks array<string>,
  all_on_twitter_clicks array<string>,
  publisher_network_segment_billed_engagements array<string>,
  publisher_network_segment_billed_charge_local_micro array<string>,
  publisher_network_segment_carousel_swipes array<string>,
  publisher_network_segment_likes array<string>,
  publisher_network_segment_poll_card_vote array<string>,
  publisher_network_segment_follows array<string>,
  publisher_network_segment_card_engagements array<string>,
  publisher_network_segment_qualified_impressions array<string>,
  publisher_network_segment_retweets array<string>,
  publisher_network_segment_replies array<string>,
  publisher_network_segment_tweets_send array<string>,
  publisher_network_segment_impressions array<string>,
  publisher_network_segment_engagements array<string>,
  publisher_network_segment_unfollows array<string>,
  publisher_network_segment_app_clicks array<string>,
  publisher_network_segment_url_clicks array<string>,
  publisher_network_segment_clicks array<string>
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
  's3://5a-datalake/raw/marketing/twitter_ads/ads_stats'

MSCK REPAIR TABLE datalake_raw.marketing_twitter_ads_stats;