drop table if exists datalake_raw.seu_barriga_invoice_report;
create external table datalake_raw.seu_barriga_invoice_report (
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
  purpose string,
  tenant_invoice_created_at string,
  landlord_invoice_created_at string
)
partitioned by (
  ym string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'mapping.id_contract'='contract-id',
  'mapping.item_from'='from'
  'mapping.item_to'='to'
  'mapping.ref_item_ym'='year-month'
  'mapping.due_date'='due-date'
  'mapping.tenant_due_date'='tenant-due-date'
  'mapping.tenant_paid_date'='tenant-paid-date'
  'mapping.tenant_status'='tenant-status'
  'mapping.landlord_due_date'='landlord-due-date'
  'mapping.landlord_paid_date'='landlord-paid-date'
  'mapping.landlord_status'='landlord-status'
  'mapping.tenant_invoice_created_at'='tenant-invoice-created-at'
  'mapping.landlord_invoice_created_at'='landlord-invoice-created-at'
)
location 's3://5a-datalake/raw/seu_barriga/invoice/report/'
;
