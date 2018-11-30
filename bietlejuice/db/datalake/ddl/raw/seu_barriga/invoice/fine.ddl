drop table if exists datalake_raw.seu_barriga_invoice_fine;
create external table datalake_raw.seu_barriga_invoice_fine (
  `contract-external-id` string,
  fine string,
  due_date string,
  `paid-date` string
)
partitioned by (
  ym string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
location 's3://5a-datalake/raw/seu_barriga/invoice/fine/'
;
