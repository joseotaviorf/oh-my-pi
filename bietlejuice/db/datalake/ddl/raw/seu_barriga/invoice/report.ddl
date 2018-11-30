drop table if exists datalake_raw.seu_barriga_invoice_report;
create external table datalake_raw.seu_barriga_invoice_report (
  `contract-id` string,
  version string,
  blocked string,
  `from` string,
  `to` string,
  description string,
  amount string,
  item string,
  `year-month` string,
  `due-date` string,
  `tenant-due-date` string,
  `tenant-paid-date` string,
  `tenant-status` string,
  `landlord-due-date` string,
  `landlord-paid-date` string,
  `landlord-status` string,
  purpose string
)
partitioned by (
  ym string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
location 's3://5a-datalake/raw/seu_barriga/invoice/report/'
;
