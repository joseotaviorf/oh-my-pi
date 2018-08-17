drop table if exists datalake_raw.workable_members;
create external table if not exists datalake_raw.workable_members (
  id string,
  name string,
  email string,
  headline string,
  role string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/workable/members/'
;

