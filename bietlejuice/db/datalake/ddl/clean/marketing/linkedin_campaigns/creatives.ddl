DROP TABLE IF EXISTS datalake_clean.marketing_linkedin_creatives;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_linkedin_creatives(
  id               string,
  id_campaign      string,
  status           string,
  type             string
)
PARTITIONED BY (
  acc        string,
  dt_created string
)
STORED AS PARQUET LOCATION
's3://5a-datalake/clean/marketing/linkedin_ads/marketing_linkedin_creatives/'

MSCK REPAIR TABLE datalake_clean.marketing_linkedin_creatives;