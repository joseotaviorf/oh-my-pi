drop table if exists datalake_clean.ods_dim_user_doorman;
create external table if not exists datalake_clean.ods_dim_user_doorman (
    sk_user_doorman bigint,
    sk_user_affiliate bigint,
    id_user_doorman bigint,
    occupation_id bigint,
    work_place_id varchar(255),
    work_address varchar(1024),
    work_street varchar(255),
    work_house_number varchar(255),
    work_neighbourhood varchar(255),
    work_city varchar(255),
    work_state varchar(255),
    work_lat decimal(18),
    work_lng decimal(18),
    recruiter varchar(255),
    subscription_source varchar(255),
    occupation_name varchar(255),
    is_active boolean,
    ts_created timestamp,
    ts_updated timestamp,
    ts_joined_program timestamp,
    ts_load timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/dim_user_doorman'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
