DROP TABLE IF EXISTS datalake_clean.marketing_linkedin_campaign_groups;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_linkedin_campaign_groups(
  id                       string,
  name                     string,
  status                   string,
  total_cost               string,
  total_cost_currency_code string,
  run_schedule_start       string,
  run_schedule_end         string,
  backfilled               string,
  id_account               string,
  account_name             string
)
PARTITIONED BY (
  acc        string,
  dt_created string
)
STORED AS PARQUET LOCATION
's3://5a-datalake/clean/marketing/linkedin_ads/marketing_linkedin_campaign_groups/'

MSCK REPAIR TABLE datalake_clean.marketing_linkedin_campaign_groups;