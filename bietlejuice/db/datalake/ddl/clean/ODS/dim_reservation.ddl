drop table if exists datalake_clean.ods_dim_reservation;
create external table if not exists datalake_clean.ods_dim_reservation(
  sk_reservation string,
  id_reservation string,
  ts_created     string,
  ts_updated     string,
  version        string,
  attempt        string,
  status         string,
  cancellation_reason         string,
  value          string,
  is_ongoing     string,
  installments   string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde' with serdeproperties (
'separatorChar' = ',',
'quoteChar' = '\"'
) location 's3://5a-datalake/clean/ods/reservation' tblproperties (
'skip.header.line.count' = '1'
);
