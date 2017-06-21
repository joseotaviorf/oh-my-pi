drop table if exists datalake_raw.seubarriga_invoice;
create external table datalake_raw.seubarriga_invoice (
  `contract-id` string,
  version string,
  blocked string,
  `from` string,
  `to` string,
  description string,
  amount string,
  item string,
  `year-month` string,
  `due-date` string
) row format serde 'org.openx.data.jsonserde.JsonSerDe'
location 's3://5a-datalake/raw/seubarriga/invoice/'
;