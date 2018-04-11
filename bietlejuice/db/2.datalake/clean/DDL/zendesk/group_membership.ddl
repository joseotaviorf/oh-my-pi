CREATE EXTERNAL TABLE datalake_clean.zendesk_group_membership (
  id string,
  url string,
  user_id string,
  group_id string,
  default boolean,
  created_at string,
  updated_at string
)
STORED AS PARQUET
LOCATION 's3://5a-datalake/clean/zendesk/group_membership/'
tblproperties ("parquet.compress"="SNAPPY");