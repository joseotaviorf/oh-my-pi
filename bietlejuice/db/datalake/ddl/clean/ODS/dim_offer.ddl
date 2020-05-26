drop table if exists datalake_clean.ods_dim_offer;
create external table if not exists datalake_clean.ods_dim_offer (
  sk_offer string,
  id_offer string,
  id_godfather string,
  id_firestore string,
  last_offered_rent string,
  original_rent string,
  original_condo string,
  dt_analysis string,
  editing string,
  status string,
  id_user string,
  id_property string,
  dt_created string,
  dt_updated string,
  dt_string string,
  offer_submitted string,
  dt_first_sent string,
  last_updated_date string,
  expiration_date string,
  first_rent_offered_by_tenant string,
  first_rent_offered_by_owner string,
  last_rent_offered_by_tenant string,
  last_rent_offered_by_owner string,
  rejection_reason string,
  type string,
  is_instant_offer string,
  app_type string,
  utm_source string,
  utm_medium string,
  utm_campaign string,
  utm_content string,
  utm_term string,
  flg_branded string,
  mkt_category string,
  mkt_flow string,
  mkt_completion string,
  mkt_origin string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string,
  mkt_platform string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/offer'
tblproperties (
  'skip.header.line.count' = '1'
)
;
