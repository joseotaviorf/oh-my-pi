drop table if exists datalake_clean.ods_dim_contract;
create external table if not exists datalake_clean.ods_dim_contract (
  sk_contract string,
  id_contract string,
  rent string,
  day_month_due string,
  guarantee string,
  type string,
  status string,
  dt_start string,
  ts_signature string,
  ts_draft_approved string,
  dt_entrance string,
  dt_intended_end string,
  dt_annulment string,
  condo_payer string,
  condo_responsible string,
  iptu_payer string,
  iptu_responsible string,
  rental_insurance_installments string,
  rental_insurance_value string,
  home_insurance_installments string,
  home_insurance_value string,
  first_rental_commission string,
  condo string,
  iptu string,
  signature_type string,
  closing_status string,
  ts_created string,
  ts_updated string,
  cancellation_reason string,
  ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/contract'
tblproperties (
  'skip.header.line.count' = '1'
)
;
