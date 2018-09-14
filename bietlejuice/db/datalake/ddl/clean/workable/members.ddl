drop table if exists datalake_clean.workable_members;
create external table datalake_clean.workable_members (
  id string,
  name string,
  email string,
  headline string,
  role string
)
stored as parquet
location 's3://5a-datalake/clean/workable/members/'
;

