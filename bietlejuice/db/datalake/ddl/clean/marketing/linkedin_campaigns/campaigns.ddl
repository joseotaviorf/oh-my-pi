DROP TABLE IF EXISTS datalake_clean.marketing_linkedin_campaigns;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_linkedin_campaigns(
  id                       string,
  name                     string,
  id_campaign_group        string,
  id_account               string,
  cost_type                string,
  daily_cost               string,
  daily_currency_code      string,
  total_cost               string,
  total_cost_currency_code string,
  unit_cost                string,
  unit_cost_currency_code  string,
  objective_type           string,
  run_schedule_start       string,
  run_schedule_end         string,
  type                     string,
  status                   string,
  locale_country           string,
  locale_language          string
)
PARTITIONED BY (
  acc        string,
  dt_created string
)
STORED AS PARQUET LOCATION
's3://5a-datalake/clean/marketing/linkedin_ads/marketing_linkedin_campaigns/'

MSCK REPAIR TABLE datalake_clean.marketing_linkedin_campaigns;