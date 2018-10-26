CREATE EXTERNAL TABLE datalake_clean.marketing_facebook_ads_ads_insights (
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
  dt_created varchar)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/facebook_ads/ads_insights/'