CREATE EXTERNAL TABLE datalake_snowplow_raw_prod.new_events (
    app_id string,
    platform string,
    etl_tstamp string,
    collector_tstamp string,
    dvce_created_tstamp string,
    ue_derivated_context1 string
)
PARTITIONED BY (
    year int,
    month int,
    day int,
    vendor string,
    event string,
    version string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES (
    "input.regex"='.*raw_event":"([\\w-]*)\\\\t([\\w]*)\\\\t([\\w :.-]*)\\\\t([\\w :.-]*)\\\\t([\\w :.-]*)\\\\t.*(\\{."schema.":\\s?."iglu:com.snowplowanalytics.snowplow/unstruct_event.*device_memory.":\\d+\\}+).*'
)
LOCATION 's3://datalake.s3.data.quintoandar.com.br/raw/snowplow-streaming-partitioned-staging'
;