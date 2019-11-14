DROP TABLE IF EXISTS datalake_raw.marketing_linkedin_campaign_groups;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_linkedin_campaign_groups(
  id                         string,
  name                       string,
  status                     string,
  total_budget_amount        string,
  total_budget_currency_code string,
  run_schedule_start         string,
  run_schedule_end           string,
  backfilled                 string,
  serving_statuses           array <string>,
  account_id                 string,
  account_name               string
)
PARTITIONED BY(
  acc string,
  dt string
)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES ('ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/linkedin_ads/campaign_groups'

  MSCK REPAIR TABLE datalake_raw.marketing_linkedin_campaign_groups;