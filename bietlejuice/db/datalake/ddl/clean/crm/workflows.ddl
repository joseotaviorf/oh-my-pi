drop table if exists datalake_clean.crm_workflows;
create external table if not exists datalake_clean.crm_workflows (
	id string,
	states string,
	id_workflow_definition string,
	workflow_definition_version string,
	id_flow string,
	ts_start string,
	ts_updated string,
	status string,
	transitions string,
	v string,
	ts_end string,
	context string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/crm/workflows/'
;