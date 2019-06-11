drop table if exists datalake_raw.zendesk_groups;
create table if not exists datalake_raw.zendesk_groups (
    id string,
    updated_at string,
    `_sdc_sequence` string,
    `_sdc_received_at` string,
    `_sdc_batched_at` string,
    `_sdc_table_version` string,
    url string,
    name string,
    deleted string,
    created_at string
)
partitioned by (
    dt string
)
row format serde
  'org.openx.data.jsonserde.JsonSerDe'
stored as inputformat
  'org.apache.hadoop.mapred.TextInputFormat'
outputformat
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
location
  's3://5a-datalake-leo-test/stitch/zendesk/groups';