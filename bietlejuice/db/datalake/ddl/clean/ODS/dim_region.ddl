drop table if exists datalake_clean.ods_dim_region;
create external table if not exists datalake_clean.ods_dim_region (
  sk_region bigint,
  id bigint,
  level string,
  name string,
  macro_id bigint,
  macro_name string,
  city_id bigint,
  city_name string,
  city_group string,
  city_ddd string,
  region_code string,
  region_code_deprecated string,
  region_code_inspector string,
  short_region_name string,
  greater_region string,
  regional string,
  regional_deprecated string,
  regional_inspection string,
  tier string,
  dt_created timestamp,
  dt_updated timestamp,
  dt_timestamp timestamp,
  dt_first_property_created timestamp,
  dt_first_booking timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/dim_region'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
