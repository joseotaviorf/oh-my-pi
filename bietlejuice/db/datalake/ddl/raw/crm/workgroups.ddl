drop table if exists datalake_raw.crm_workgroups;
create external table if not exists datalake_raw.crm_workgroups (
  id string,
  task_types array<string>,
  title string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true',
  'mapping.id'='_id',
  'mapping.task_types'='taskTypes'
)
location 's3://5a-datalake/raw/crm/workgroups/'
;