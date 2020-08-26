drop table if exists datalake_clean.ods_dim_user_affiliate;
create external table if not exists datalake_clean.ods_dim_user_affiliate (
    sk_user_affiliate string,
    id_user_affiliate string,
    sk_user_indicated_by string,
    ts_joined_program string,
    is_active string,
    ts_updated string,
    ts_created string,
    origin string,
    type string,
    marketing_city_group string,
    regional string,
    is_realstate_agent string,
    is_photographer string,
    tracking_source string,
    tracking_medium string,
    tracking_campaign string,
    tracking_content string,
    tracking_term string,
    tracking_platform string,
    tracking_device_type string,
    tracking_country string,
    tracking_state string,
    tracking_city string,
    mkt_origin string,
    mkt_channel string,
    mkt_medium string,
    mkt_source string,
    ts_load string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/user_affiliate'
tblproperties (
  'skip.header.line.count' = '1'
)
;