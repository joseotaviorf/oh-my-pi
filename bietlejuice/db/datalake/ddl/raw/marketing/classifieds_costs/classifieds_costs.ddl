DROP TABLE datalake_raw.marketing_classifieds_costs;

CREATE EXTERNAL TABLE datalake_raw.marketing_classifieds_costs (
  `source` string,
  `cost` string)
PARTITIONED BY (
  acc string,
  dt string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json'   = 'true'
)
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/classifieds_costs/'

MSCK REPAIR TABLE datalake_raw.marketing_classifieds_costs;