drop table if exists datalake_clean.invoice;
create external table datalake_clean.invoice (
  contract_id bigint,
  version string,
  blocked boolean,
  `from` string,
  `to` string,
  description string,
  amount double,
  item string,
  year_month string,
  due_date string
)
stored as parquet
location 's3://5a-datalake/clean/seubarriga/invoice/'
;