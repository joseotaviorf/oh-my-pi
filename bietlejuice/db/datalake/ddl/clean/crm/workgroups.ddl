drop table if exists datalake_clean.crm_workgroups;
create external table if not exists datalake_clean.crm_workgroups (
  id string,
  task_type string,
  title string
)
stored as parquet
location 's3://5a-datalake/clean/crm/workgroups/'
;