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
  dt_due string,
  dt_tenant_due string,
  dt_tenant_paid string,
  tenant_status string,
  dt_landlord_due string,
  dt_landlord_paid string,
  landlord_status string,
  days_delayed string,
  purpose string,
  dt_tenant_invoice_created string,
  dt_landlord_invoice_created string,
)
partitioned by (
  ym string
)
stored as parquet
location 's3://5a-datalake/clean/seu_barriga/invoice/report/'
;
