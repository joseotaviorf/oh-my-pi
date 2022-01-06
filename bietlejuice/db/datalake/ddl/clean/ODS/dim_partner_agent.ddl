drop table if exists datalake_clean.ods_dim_partner_agent;
create external table if not exists datalake_clean.ods_dim_partner_agent (
    sk_partner_agent bigint,
    id_partner_agent bigint,
    id_user bigint,
    id_partner bigint,
    status_partner_agent varchar(255),
    type varchar(255),
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
  's3://dw.s3.data.quintoandar.com.br/public/dim_partner_agent'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
