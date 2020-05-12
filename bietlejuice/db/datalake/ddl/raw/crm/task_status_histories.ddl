drop table if exists datalake_raw.crm_task_status_histories;
create external table datalake_raw.crm_task_status_histories (
  task_status_histories_entry string
)
partitioned by (
  dt string
)
location 's3://5a-datalake/raw/crm/task_status_histories'
;