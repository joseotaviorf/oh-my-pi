drop table if exists datalake_clean.ods_dim_offer;

create external table if not exists datalake_clean.ods_dim_offer (
  sk_offer string,
  id_offer string,
  id_godfather string,
  renting_value string,
  renting_original_value string,
  condo_original_value string,
  dt_analysis string,
  editing string,
  status string,
  id_user string,
  id_property string,
  dt_created string,
  dt_updated string,
  dt_string string,
  offer_submitted string,
  ultimo_update_edicao string,
  dt_first_sent string,
  last_updated_date string,
  expiration_date string,
  last_rent_value_offered_by_tenant string,
  last_rent_value_offered_by_owner string,
  total_rent_value string,
  rejection_reason string,
  animais_condition string,
  quando_vai_mudar_condition string,
  quem_vai_morar_condition string,
  special_conditions_count string,
  remove_conditions string,
  include_conditions string,
  maintenance_or_repair_conditions string,
  replace_or_modify_conditions string,
  price_conditions string,
  other_conditions string,
  type string
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
