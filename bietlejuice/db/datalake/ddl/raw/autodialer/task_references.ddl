DROP TABLE datalake_raw.autodialer_task_references;

CREATE EXTERNAL TABLE datalake_raw.autodialer_task_references (
  `_class` string,
  `_id` string,
  active boolean,
  agentid string,
  assignee string,
  autodialerresponse string,
  contactinfo string,
  createddate string,
  dialstatus string,
  score string,
  snoozeduntil string,
  taskid string,
  tasklink string,
  tasktype string,
  updateddate string)
PARTITIONED BY (
  dt_extraction string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
LOCATION
  's3://5a-datalake/raw/autodialer/task_references/'

msck repair table datalake_raw.autodialer_task_references