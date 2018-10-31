drop table if exists datalake_clean.invoice;
create external table datalake_clean.invoice (
  contract_id bigint,
  version string,
  blocked boolean,
  `_from` string,
  `_to` string,
  description string,
  amount double,
  item string,
  ref_item_ym string,
  due_date string,
  tenant_due_date string,
  tenant_paid_date string,
  tenant_status string,
  landlord_due_date string,
  landlord_paid_date string,
  landlord_status string,
  delayed_days double,
  purpose string
)
partitioned by (
  ym string
)
stored as parquet
location 's3://5a-datalake/clean/seubarriga/invoice/report/'
;

msck repair table datalake_clean.invoice;
