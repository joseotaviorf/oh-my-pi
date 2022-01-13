drop table if exists datalake_clean.ods_dim_visit;

create external table if not exists datalake_clean.ods_dim_visit (
  sk_visit int,
  id_visit int,
  cd_visit varchar(200),
  day_visit date,
  slot int,
  slot_count int,
  type integer,
  status int,
  booking_type varchar(255),
  dt_created timestamp,
  dt_updated timestamp,
  dt_timestamp timestamp
);

ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/dim_visit'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')