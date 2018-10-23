CREATE EXTERNAL TABLE datalake_clean.marketing_google_ads_keywords(
    account_id varchar,
    adgroup_id varchar,
    adgroup_name varchar,
    campaign_id varchar,
    campaign_name varchar,
    clicks varchar,
    click_type varchar,
    cost varchar,
    date varchar,
    device varchar,
    keyword_id varchar,
    impressions varchar,
    match_type varchar,
    labels varchar,
    criteria varchar,
    account_name varchar)
PARTITIONED BY (
  acc varchar,
  dt_created varchar)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/google_ads/keywords_performance_report/'