drop table if exists datalake_clean.crm_workflow_transitions;
create external table if not exists datalake_clean.crm_workflow_transitions (
  id string,
  id_workflow string,
  id_task_from string,
  id_task_to string,
  assignment_method string,
  definition_task_from string,
  definition_task_to string,
  is_end_of_workflow string,
  context string,
  ts_transitioned string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/crm/workflow_transitions/'
;
