drop table if exists datalake_clean.ods_dim_contract;
create external table if not exists datalake_clean.ods_dim_contract (
  sk_contract string,
  id_contract string,
  email_invoice string,
  renting_value string,
  property_number string,
  day_month_due string,
  guarantee string,
  contract_type string,
  contract_status string,
  dt_calc_affiliate_comission string,
  dt_calc_agent_comission string,
  dt_contract_start string,
  dt_signature string,
  dt_draft_approved string,
  dt_entrance string,
  dt_contract_intended_end string,
  dt_contract_annulment string,
  bank_name string,
  condo_payer string,
  iptu_payer string,
  condo_responsible string,
  iptu_responsible string,
  rental_insurance_installments string,
  rental_insurance_value string,
  home_insurance_installments string,
  home_insurance_value string,
  first_rental_comission string,
  condo_value string,
  iptu_value string,
  signature_type string,
  dt_send_eletronic_contract string,
  closing_status string,
  contract_signed string,
  contract_administration_signed string,
  contract_authorization_signed string,
  contract_renting_signed string,
  dt_ownership_changed string,
  dt_created string,
  dt_updated string,
  dt_timestamp string
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
