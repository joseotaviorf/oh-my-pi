  drop table if exists datalake_raw.crm_task_titles;
create external table if not exists datalake_raw.crm_task_titles (
  id string,
  description string,
  title string,
  workgroup_ids array<string>
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true',
  'mapping.id'='_id',
  'mapping.workgroup_ids'='workgroupids'
)
location 's3://5a-datalake/raw/crm/task_titles/'
;