drop table if exists datalake_clean.ods_dim_condo;
create external table if not exists datalake_clean.ods_dim_condo (
    sk_condo bigint,
    id_condo bigint,
    neighborhood string,
    zipcode string,
    city string,
    address string,
    lat decimal(10,7),
    lng decimal(10,7),
    name string,
    number string,
    ts_created timestamp,
    ts_updated timestamp,
    ts_load timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/dim_condo'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')