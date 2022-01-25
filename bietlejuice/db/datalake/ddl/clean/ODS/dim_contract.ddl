drop table if exists datalake_clean.ods_dim_contract;
create external table if not exists datalake_clean.ods_dim_contract (
  sk_contract bigint,
  id_contract bigint,
  rent numeric(14,2),
  day_month_due smallint,
  guarantee string,
  type string,
  status string,
  condo_payer string,
  condo_responsible string,
  iptu_payer string,
  iptu_responsible string,
  rental_insurance_installments smallint,
  rental_insurance_value numeric(14,2),
  home_insurance_installments smallint,
  home_insurance_value numeric(14,2),
  first_rental_commission numeric(14,2),
  monthly_administration_fee numeric(14,2),
  condo numeric(14,2),
  iptu numeric(14,2),
  tenant_service_fee numeric(14,2),
  signature_type string,
  closing_status string,
  cancellation_reason string,
  version string,
  is_b2b boolean,
  b2b_type string,
  b2b_prime_type string,
  is_ongoing_contract boolean,
  is_tenant_service_fee_opt_out boolean,
  dt_start date,
  dt_entrance date,
  dt_intended_end date,
  dt_annulment date,
  ts_created timestamp,
  ts_updated timestamp,
  ts_signature timestamp,
  ts_draft_approved timestamp,
  ts_canceled timestamp,
  ts_tenant_service_fee_opt_out timestamp,
  ts_analyst_annulment_input timestamp,
  ts_load timestamp
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/dim_contract'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
