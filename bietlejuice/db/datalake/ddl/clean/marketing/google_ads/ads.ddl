CREATE EXTERNAL TABLE datalake_clean.marketing_google_ads_ads (
   account_id varchar,
    adgroup_id varchar,
    adgroup_name varchar,
    ad_type varchar,
    campaign_id varchar,
    campaign_name varchar,
    clicks varchar,
    click_type varchar,
    cost varchar,
    keyword_id varchar,
    date varchar,
    device varchar,
    ad_id varchar,
    impressions varchar,
    labels varchar,
    image_creative_name varchar,
    account_name varchar,
    description varchar,
    description1 varchar,
    description2 varchar)
PARTITIONED BY (
  acc varchar,
  dt_created varchar)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/google_ads/marketing_google_ads_ads/'