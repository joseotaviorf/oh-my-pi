drop table if exists datalake_clean.seu_barriga_invoice_report;
create external table datalake_clean.seu_barriga_invoice_report (
  contract_id string,
  version string,
  blocked string,
  `_from` string,
  `_to` string,
  description string,
  amount string,
  item string,
  ref_item_ym string,
  due_date string,
  tenant_due_date string,
  tenant_paid_date string,
  tenant_status string,
  landlord_due_date string,
  landlord_paid_date string,
  landlord_status string,
  delayed_days string,
  purpose string
)
partitioned by (
  ym string
)
stored as parquet
location 's3://5a-datalake/clean/seu_barriga/invoice/report/'
;
