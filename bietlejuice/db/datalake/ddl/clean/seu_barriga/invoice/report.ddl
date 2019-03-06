drop table if exists datalake_clean.seu_barriga_invoice_report;
create external table datalake_clean.seu_barriga_invoice_report (
  id_contract string,
  version string,
  blocked string,
  item_from string,
  item_to string,
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
  purpose string,
  tenant_invoice_created_at string,
  landlord_invoice_created_at string
)
partitioned by (
  ym string
)
stored as parquet
location 's3://5a-datalake/clean/seu_barriga/invoice/report/'
;
