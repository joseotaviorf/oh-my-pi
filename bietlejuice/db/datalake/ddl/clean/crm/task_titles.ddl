drop table if exists datalake_clean.crm_task_titles;
create external table if not exists datalake_clean.crm_task_titles (
  id string,
  description string,
  title string,
  workgroup_ids string
)
stored as parquet
location 's3://5a-datalake/clean/crm/task_titles/'
;