drop table if not exists datalake_raw.godfather_topic;
create external table if not exists datalake_raw.godfather_topic (
  id string,
  created_at string,
  updated_at string,
  version string,
  firestore_id string,
  status string,
  type string,
  offer_id string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/godfather/business/topic'
;