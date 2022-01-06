drop table if exists datalake_clean.ods_dim_partner;
create external table if not exists datalake_clean.ods_dim_partner (
    sk_partner bigint,
    id_partner bigint,
    id_amplitude_device varchar(255),
    name varchar(255),
    trade_name varchar(255),
    phone varchar(255),
    email varchar(255),
    cnpj varchar(255),
    creci varchar(255),
    type varchar(255),
    city varchar(255),
    utm_campaign varchar(255),
    utm_medium varchar(255),
    utm_source varchar(255),
    ts_joined_partnership timestamp,
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
  's3://dw.s3.data.quintoandar.com.br/public/dim_partner'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
