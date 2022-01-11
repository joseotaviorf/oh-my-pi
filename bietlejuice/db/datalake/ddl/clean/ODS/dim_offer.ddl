drop table if exists datalake_clean.ods_dim_offer;
create external table if not exists datalake_clean.ods_dim_offer (
  sk_offer int,
  id_offer int,
  id_godfather int,
  id_firestore string,
  id_user int,
  id_property int,
  editing string,
  status string,
  rejection_reason string,
  type string,
  app_type string,
  utm_source string,
  utm_medium string,
  utm_campaign string,
  utm_content string,
  utm_term string,
  mkt_category string,
  mkt_flow string,
  mkt_completion string,
  mkt_origin string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string,
  mkt_platform string,
  last_offered_rent int,
  original_rent int,
  original_condo int,
  is_instant_offer boolean,
  flg_branded boolean,
  offer_submitted boolean,
  first_rent_offered_by_tenant decimal(18,4),
  first_rent_offered_by_owner decimal(18,4),
  last_rent_offered_by_tenant decimal(18,4),
  last_rent_offered_by_owner decimal(18,4),
  last_updated_date timestamp,
  expiration_date timestamp,
  dt_analysis timestamp,
  dt_first_sent timestamp,
  dt_created timestamp,
  dt_updated timestamp,
  dt_timestamp timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/dim_offer'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')

