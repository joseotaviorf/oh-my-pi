DROP TABLE IF EXISTS datalake_raw.asterisk_config;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.asterisk_config (
    queue_id STRING,
    queue_name STRING,
    agent_extension STRING,
    agent_name STRING,
    ura_id STRING,
    ura_option STRING,
    ura_name STRING,
    ura_code STRING,
    dt_created STRING,
    dt_updated STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
   "separatorChar" = ",",
   "quoteChar"     = "\""
)
LOCATION 's3://5a-datalake/raw/asterisk/config/';