DROP TABLE datalake_raw.task_references;

CREATE EXTERNAL TABLE datalake_raw.task_references (
  `_class` string,
  `_id` string,
  `active` boolean,
  `agentid` string,
  `assignee` string,
  `autodialerresponse` string,
  `contactinfo` varchar(1024),
  `createddate` string,
  `dialstatus` string,
  `score` string,
  `snoozeduntil` string,
  `taskid` string,
  `tasklink` string,
  `tasktype` string,
  `updateddate` string)
PARTITIONED BY (
  `dt` string)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';'
)
LOCATION
  's3://5a-datalake/raw/autodialer/task_references/'
TBLPROPERTIES (
  'skip.header.line.count'='1')

msck repair table datalake_raw.task_references