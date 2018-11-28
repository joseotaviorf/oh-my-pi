drop table if exists datalake_clean.seu_barriga_invoice_fine;
create external table datalake_clean.seu_barriga_invoice_fine (
  contract_id bigint,
  fine double,
  due_date string,
  paid_date string
)
partitioned by (
  ym string
)
stored as parquet
location 's3://5a-datalake/clean/seu_barriga/invoice/fine/'
;
