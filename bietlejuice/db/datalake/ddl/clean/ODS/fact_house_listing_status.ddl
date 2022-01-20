drop table if exists datalake_clean.ods_fact_house_listing_status;
create external table if not exists datalake_clean.ods_fact_house_listing_status (
  sk_house_listing bigint,
  sk_region bigint,
  sk_first_publication_date bigint,
  sk_status_start_date bigint,
  sk_status_end_date bigint,
  ts_status_start timestamp,
  ts_status_end timestamp,
  status_history string,
  status_change_reason varchar(5000),
  is_last_status_of_day boolean,
  ts_load timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/fact_house_listing_status'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
