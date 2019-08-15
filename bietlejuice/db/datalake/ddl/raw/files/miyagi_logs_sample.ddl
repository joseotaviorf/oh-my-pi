drop table if exists datalake_raw.miyagi_logs_sample;
create external table if not exists datalake_raw.miyagi_logs_sample (
  index string,
  type string,
  id string,
  score double,
  source struct <app:string, created_at:string, message:string>
)
row format serde
  'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"',
  'mapping.index'='_index',
  'mapping.type'='_type',
  'mapping.id'='_id',
  'mapping.score'='_score',
  'mapping.source'='_source',
  'mapping.app' = 'app',
  'mapping.created_at'='@timestamp',
  'mapping.message'='message'
)
stored as inputformat
  'org.apache.hadoop.mapred.TextInputFormat'
outputformat
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
location 
  's3://5a-datalake/raw/files/miyagi/'
;