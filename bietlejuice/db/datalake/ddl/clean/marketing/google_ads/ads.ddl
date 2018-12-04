DROP TABLE datalake_clean.marketing_google_ads;

CREATE EXTERNAL TABLE datalake_clean.marketing_google_ads (
   account_id string,
    adgroup_id string,
    adgroup_name string,
    ad_type string,
    campaign_id string,
    campaign_name string,
    clicks string,
    click_type string,
    cost string,
    keyword_id string,
    date string,
    device string,
    ad_id string,
    impressions string,
    labels string,
    image_creative_name string,
    account_name string,
    description string,
    description1 string,
    description2 string)
PARTITIONED BY (
  acc string,
  dt_created string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/google_ads/marketing_google_ads/'

MSCK REPAIR TABLE datalake_clean.marketing_google_ads;