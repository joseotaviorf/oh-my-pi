DROP TABLE datalake_clean.marketing_google_keywords;

CREATE EXTERNAL TABLE datalake_clean.marketing_google_keywords (
    account_id string,
    adgroup_id string,
    adgroup_name string,
    campaign_id string,
    campaign_name string,
    clicks string,
    click_type string,
    cost string,
    date string,
    device string,
    keyword_id string,
    impressions string,
    match_type string,
    labels string,
    criteria string,
    account_name string)
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/google_ads/keywords_performance_report/'

MSCK REPAIR TABLE datalake_clean.marketing_google_keywords;