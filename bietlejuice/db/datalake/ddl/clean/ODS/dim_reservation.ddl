drop table if exists datalake_clean.ods_dim_reservation;
create external table if not exists datalake_clean.ods_dim_reservation(
  sk_reservation bigint,
  id_reservation bigint,
  ts_created timestamp,
  ts_updated timestamp,
  version int,
  attempt int,
  status varchar(255),
  cancellation_reason varchar(255),
  value decimal(19, 2),
  is_ongoing int,
  installments int
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/dim_reservation'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
