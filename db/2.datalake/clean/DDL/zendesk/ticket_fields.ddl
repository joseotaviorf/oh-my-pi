CREATE EXTERNAL TABLE datalake_clean.zendesk_ticket_fields (
  id string,
  ticket_id string,
  value string
)
STORED AS PARQUET
LOCATION 's3://5a-datalake/clean/zendesk/ticket_fields/'
tblproperties ("parquet.compress"="SNAPPY");