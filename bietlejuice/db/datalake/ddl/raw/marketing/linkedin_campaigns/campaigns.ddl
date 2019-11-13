DROP TABLE IF EXISTS datalake_raw.marketing_linkedin_campaigns;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_linkedin_campaigns(
  id                                  string,
  name                                string,
  associated_entity                   string,
  audience_expansion_enabled          string,
  campaign_group_id                   string,
  cost_type                           string,
  creative_selection                  string,
  daily_budget_amount                 string,
  daily_budget_currencyCode           string,
  locale_country                      string,
  locale_language                     string,
  objective_type                      string,
  offsite_preferences                 string,
  run_schedule_start                  string,
  run_schedule_end                    string,
  targeting_excluded_targeting_facets string,
  targeting_included_targeting_facets string,
  targeting_criteria                  string,
  total_budget_amount                 string,
  total_budget_currencyCode           string,
  type                                string,
  unit_cost_amount                    string,
  unit_cost_currency_code             string,
  version_tag                         string,
  status                              string,
  optimizationTargetType              string,
  format                              string,
  account_id                          string
)
PARTITIONED BY(
  acc string,
  dt  string
)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES ('ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/linkedin_ads/campaigns'

MSCK REPAIR TABLE datalake_raw.marketing_linkedin_campaigns;