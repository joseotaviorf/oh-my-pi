drop table if exists datalake_clean.ods_sale_fact_listing_sale_flows;
create external table datalake_clean.ods_sale_fact_listing_sale_flows (
  ods_id bigint,
  sk_house_listing bigint,
  sk_region bigint,
  sk_sale_flow bigint,
  sk_booking bigint,
  sk_owner bigint,
  sk_user_agent bigint,
  sk_client bigint,
  sk_visit bigint,
  sk_house_first_listing_date bigint,
  sk_house_listing_date bigint,
  sk_house_listing_de_publication_date bigint,
  sk_booking_created_date bigint,
  sk_visit_date bigint,
  sk_agent_review_rating_date bigint,
  visit_created_type varchar(255),
  funnel_step varchar(255),
  funnel_step_drop_reason varchar(255),
  flg_visit_completed boolean,
  flg_visit_performed boolean,
  flg_visit_created_from_app boolean,
  flg_visit_last_updated_from_app boolean,
  days_booking_created_to_visit decimal(14,2),
  days_user_created_to_visit decimal(14,2),
  days_house_listing_to_visit decimal(14,2),
  ts_load timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/sale/fact_listing_sale_flows'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
