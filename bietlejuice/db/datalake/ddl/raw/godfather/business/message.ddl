drop table if not exists datalake_raw.godfather_message;
create external table if not exists datalake_raw.godfather_message (
  id string,
  created_at string,
  updated_at string,
  version string,
  firestore_id string,
  iteration string,
  text string,
  turn string,
  type string,
  topic_id string,
  author_id string,
  raw_document string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/godfather/business/message'
;