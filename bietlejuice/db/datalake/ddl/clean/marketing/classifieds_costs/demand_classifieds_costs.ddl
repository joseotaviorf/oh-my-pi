DROP TABLE datalake_clean.marketing_demand_classifieds_costs;

CREATE EXTERNAL TABLE datalake_clean.marketing_demand_classifieds_costs (
  medium string,
  source string,
  cost string
)
PARTITIONED BY (
  acc string,
  dt_created string
)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/classifieds_costs/marketing_demand_classifieds_costs/'

MSCK REPAIR TABLE datalake_clean.marketing_demand_classifieds_costs;