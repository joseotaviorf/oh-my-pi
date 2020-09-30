DROP TABLE IF EXISTS datalake_clean.marketing_lifull_campaigns;

CREATE EXTERNAL TABLE datalake_clean.marketing_lifull_campaigns(
  `id`              string,
  `name`            string,
  `account_name`    string,
  `clicks`          string,
  `desktop_cost`    string,
  `mobile_cost`     string,
  `total_cost`      string,
  `curr_date`       string)
PARTITIONED BY(
  acc string,
  group_name string,
  dt_created  string)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/lifull_campaigns/marketing_lifull_campaigns/'
;

MSCK REPAIR TABLE datalake_clean.marketing_lifull_campaigns;