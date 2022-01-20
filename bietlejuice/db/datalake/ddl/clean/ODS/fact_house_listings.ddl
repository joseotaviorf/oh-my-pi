drop table if exists datalake_clean.ods_fact_house_listings;
create external table if not exists datalake_clean.ods_fact_house_listings (
    sk_house_listing bigint,
    sk_owner bigint,
    sk_region bigint,
    sk_user_registration bigint,
    sk_contract bigint,
    sk_condo bigint,
    sk_user_partner_agent bigint,
    sk_partner bigint,
    sk_autonomous_agent bigint,
    sk_stranded_date bigint,
    days_listing_to_contract_signed int,
    days_listing_to_depublication int,
    days_ended_rental_to_relisting int,
    days_relisting_to_re_rental int,
    days_ended_rental_to_re_rented int,
    nr_renting smallint,
    order_renting smallint,
    ts_load timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/fact_house_listings'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')