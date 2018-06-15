drop table datalake_raw.lead_tasks;

create external table datalake_raw.lead_tasks (
  task_id string,
  task_status string,
  rep_id string,
  first_rep_id string,
  lead_id string,
  number_of_reschedules string,
  dt_created string,
  dt_closed string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/crm/lead_tasks/'
tblproperties (
  'skip.header.line.count' = '1'
)
;