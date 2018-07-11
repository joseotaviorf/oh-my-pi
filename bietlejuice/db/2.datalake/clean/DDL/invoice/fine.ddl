drop table if exists datalake_clean.invoice_fine;
create external table datalake_clean.invoice_fine (
  contract_id bigint,
  fine double,
  due_date string,
  paid_date string
)
partitioned by (
  ym string
)
stored as parquet
location 's3://5a-datalake/clean/seubarriga/invoice/fine/'
;

msck repair table datalake_clean.invoice_fine;
