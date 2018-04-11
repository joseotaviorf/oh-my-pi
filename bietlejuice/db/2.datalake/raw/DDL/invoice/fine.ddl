drop table if exists datalake_raw.seubarriga_invoice_fine;
create external table datalake_raw.seubarriga_invoice_fine (
  `contract-external-id` string,
  fine string,
  due_date string,
  `paid-date` string
)
partitioned by (
  ym string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
location 's3://5a-datalake/raw/seubarriga/invoice/fines/'
;

msck repair table datalake_raw.seubarriga_invoice_fine;
