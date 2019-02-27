drop table if exists datalake_raw.seu_barriga_invoice_fine;
create external table datalake_raw.seu_barriga_invoice_fine (
  external_id_contract string,
  fine string,
  due_date string,
  paid_date string
)
partitioned by (
  ym string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'mapping.external_id_contract'='contract-external-id',
  'mapping.due_date'='due-date'
  'mapping.paid_date'='paid-date'
)
location 's3://5a-datalake/raw/seu_barriga/invoice/fine/'
;
