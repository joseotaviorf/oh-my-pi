DROP TABLE IF EXISTS datalake_clean.marketing_trovit_campaigns;

CREATE EXTERNAL TABLE datalake_clean.marketing_trovit_campaigns(
  `id`          string,
  `name`        string,
  `clicks`      string,
  `cost`        string,
  `curr_date`   string)
PARTITIONED BY(
  acc string,
  dt_created  string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/trovit_campaigns/marketing_trovit_campaigns/'
;

MSCK REPAIR TABLE datalake_clean.marketing_trovit_campaigns;