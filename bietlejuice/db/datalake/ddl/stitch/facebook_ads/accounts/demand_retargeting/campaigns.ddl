CREATE EXTERNAL TABLE stitch.`facebook_ads_demand_retargeting_campaigns`(
  `effective_status` string,
  `updated_time` string,
  `id` string,
  `name` string,
  `_sdc_table_version` string,
  `objective` string,
  `_sdc_received_at` string,
  `_sdc_sequence` string,
  `buying_type` string,
  `start_time` string,
  `account_id` string,
  `_sdc_batched_at` string,
  `ads` struct<
    data:array<
      struct<id:string>
    >
  >,
  `_sdc_extracted_at` string
)
PARTITIONED BY (
  `dt` string
)
ROW FORMAT SERDE 
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json' = 'true'
)
LOCATION
  's3://5a-datalake/stitch_data/facebook_ads_demand_retargeting/campaigns/'