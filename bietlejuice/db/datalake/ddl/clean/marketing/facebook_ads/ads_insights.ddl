DROP TABLE datalake_clean.marketing_facebook_ads_ads_insights;

CREATE EXTERNAL TABLE datalake_clean.marketing_facebook_ads_ads_insights (
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
    link_clicks string)
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/facebook_ads/ads_insights/'

MSCK REPAIR TABLE datalake_clean.marketing_facebook_ads_ads_insights;