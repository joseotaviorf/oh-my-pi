drop table if not exists datalake_raw.godfather_offer;
create external table if not exists datalake_raw.godfather_offer (
  id string,
  created_at string,
  updated_at string,
  version string,
  firestore_id string,
  status string,
  rent_flow_id string,
  resident_info_id string,
  original_rent string,
  rent string,
  turn string,
  rejection_reason string,
  type string,
  offer_status string,
  code string,
  original_condo string,
  original_iptu string,
  original_home_insurance string,
  first_sent_at string,
  last_sent_at string,
  expiration_date string,
  visualized_at string,
  iteration string,
  visualized string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/godfather/business/offer'
;