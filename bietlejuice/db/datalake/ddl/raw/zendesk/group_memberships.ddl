drop table if exists stitch.group_memberships;
create external table if not exists stitch.group_memberships (
    created_at string,
    default string,
    group_id string,
    id string,
    updated_at string,
    url string,
    user_id string
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