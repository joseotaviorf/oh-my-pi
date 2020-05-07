drop table if exists datalake_raw.crm_workflows;
create external table datalake_raw.crm_workflows (
  workflows_entry string
)
partitioned by (
  dt string
)
location 's3://5a-datalake/raw/crm/workflows'
;