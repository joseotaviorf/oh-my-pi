drop table if exists datalake_clean.ods_fact_house_listings;
create external table if not exists datalake_clean.ods_fact_house_listings (
  sk_house_listing string,
  sk_owner string,
  sk_region string,
  sk_user_registration string,
  sk_contract string,
  sk_condo string,
  days_first_listing_to_contract_signed string,
  days_listing_to_depublication string,
  nr_renting string,
  ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/house_listings'
tblproperties (
  'skip.header.line.count' = '1'
)
;