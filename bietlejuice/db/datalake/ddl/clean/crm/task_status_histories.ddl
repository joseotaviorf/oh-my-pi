drop table if exists datalake_clean.crm_task_status_histories;
create external table if not exists datalake_clean.crm_task_status_histories (
    id string,
    v string,
    histories string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/crm/task_status_histories/'
;