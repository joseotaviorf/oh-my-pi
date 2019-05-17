drop table if exists stitch.group_memberships;
create external table if not exists stitch.group_memberships (
    user_id string,
    url string,
    group_id string,
    id string,
    `_sdc_table_version` string,
    updated_at string,
    `_sdc_received_at` string,
    `_sdc_sequence` string,
    created_at string,
    `_sdc_batched_at` string,
    default string
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
  's3://5a-datalake-leo-test/stitch/zendesk/group_memberships/';