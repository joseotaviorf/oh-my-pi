CREATE EXTERNAL TABLE datalake_clean.zendesk_group (
  id string,
  url string,
  name string,
  deleted boolean,
  created_at string,
  updated_at string
)
STORED AS PARQUET
LOCATION 's3://5a-datalake/clean/zendesk/group/'
tblproperties ("parquet.compress"="SNAPPY");