drop table if exists datalake_raw.taxonomy_growth;

create external table datalake_raw.taxonomy_growth (
    lead_type string,
    lead_origin string,
    lead_tracking_medium string,
    lead_tracking_source string,
    affiliate_type string,
    is_agent_referral string,
    lead_referring_category string,
    is_branded string,
    is_ops_direct_register string,
    mkt_origin string,
    mkt_channel string,
    mkt_medium string,
    mkt_source string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ';',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/gsheets/taxonomy_growth/'
tblproperties (
  'skip.header.line.count' = '1'
)
;