CREATE EXTERNAL TABLE IF NOT EXISTS {db}.{table_name} (
  `adid` string,
  `dma` string,
  `is_attribution_event` boolean,
  `device_brand` string,
  `sample_rate` string,
  `processed_time` string,
  `server_received_time` string,
  `location_lat` string,
  `server_upload_time` string,
  `os_name` string,
  `device_manufacturer` string,
  `user_id` string,
  `platform` string,
  `location_lng` string,
  `event_time` string,
  `uuid` string,
  `amplitude_id` bigint,
  `user_properties` string,
  `city` string,
  `amplitude_attribution_ids` array<string>,
  `library` string,
  `country` string,
  `paying` string,
  `device_id` string,
  `client_event_time` string,
  `insert_id` string,
  `os_version` string,
  `schema` bigint,
  `client_upload_time` string,
  `data` string,
  `device_type` string,
  `event_properties` string,
  `session_id` bigint,
  `user_creation_time` string,
  `region` string,
  `device_family` string,
  `device_model` string,
  `app` bigint,
  `event_id` bigint,
  `start_version` string,
  `idfa` string,
  `language` string,
  `amplitude_event_type` string,
  `ip_address` string,
  `device_carrier` string,
  `version_name` string)
PARTITIONED BY (
  `year` int,
  `month` int,
  `day` int,
  `event_type` string)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  '{path}'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
