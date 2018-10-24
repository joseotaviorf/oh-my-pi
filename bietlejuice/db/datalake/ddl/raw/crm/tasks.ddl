create external table datalake_raw.crm_tasks (
  task_entry string
)
partitioned by ( 
  dt string
)
stored as textfile
location 's3://5a-datalake/raw/crm/tasks'
;